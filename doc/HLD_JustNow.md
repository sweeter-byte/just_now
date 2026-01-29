# Just Now - High-Level Design (HLD)

**文档版本**：V1.4 (Industrial Standard)
**最后更新**：2026-01-29
**参考文档**：SRS_JustNow_Merged.md V3.1

---

## 1. 系统架构设计 (System Architecture)

### 1.1 总体架构图 (Architecture Diagram)

系统采用 **Client-Gateway-Services** 架构，API Gateway 统一承担鉴权与限流职责。

```mermaid
graph TD
    subgraph Client [Android Client]
        A[Floating Service] -->|HTTPS / TLS 1.2+| GW[API Gateway]
        RUM[RUM SDK] -.->|Async Metrics| OBS[Observability]
    end

    subgraph Cloud [Cloud Services]
        subgraph Gateway_Layer [Smart Gateway]
            GW -->|Verify Signature| IAM[Identity Module (Plugin)]
            GW -->|Global Rate Limit| REDIS[Redis Counter]
        end
        
        GW -->|Route| ORC[Orchestrator]
        
        subgraph Core_Logic
            ORC -->|Audio| ASR[ASR Service]
            ASR -->|Text| LLMGW[LLM Gateway]
            LLMGW -->|Prompt + Fallback| LLM[LLM Provider]
            LLMGW -->|Mock| MOCK[Mock Service]
        end
        
        subgraph Config_Plane
            Git[Git Repo] -->|CI/CD Build| ART[Artifact Store]
            ART -->|Pull Config| LLMGW
        end
        
        subgraph Observability_Plane
             OBS -->|Logs/Traces| ELK
             OBS -->|Metrics| PROM[Prometheus]
        end
    end
```

### 1.2 模块职责与边界

| 模块 | 关键职责 | 技术选型 |
| :--- | :--- | :--- |
| **API Gateway** | 统一接入口。集成 **Identity Module** (中间件) 进行签名校验 (`HMAC`) 和设备鉴权。**Mandatory Edge Protection**: IP/Device Rate Limit, Size/Type Validation, Bot Filtering. (Optional: Cloud WAF). | Kong / Nginx + Lua |
| **Orchestrator** | 业务流程编排。负责串联 ASR -> LLM，管理全链路 Trace ID。 | backend-for-frontend (BFF) |
| **LLM Gateway** | 模型路由、重试熔断、Prompt 配置管理。 | Custom Service / LangChain |
| **Config Center** | 存储 Prompt Version 和 Mock Scenarios 的**构建产物** (Artifacts)。 | Consul / Etcd |

| **Config Center** | 存储 Prompt Version 和 Mock Scenarios 的**构建产物** (Artifacts)。 | Consul / Etcd |

### 1.3 Engineering Optimizations (工程优化)
1.  **ASR Latency Strategy**:
    *   为满足 800ms 极致体验，客户端**优先调用 Android Native SpeechRecognizer**；Cloud ASR 仅作为复杂场景兜底。
2.  **Demo Scenario Injector**:
    *   允许通过 HTTP Header `X-Mock-Scenario` (e.g., `taxi_rainy_day`) 强制 LLM Gateway 加载预设 Context，确保演示稳定性。

## 2. 系统韧性 (Resilience & Reliability)

### 2.1 错误分类与 HTTP Status 契约 (Strict Industrial Standard)

**核心原则**：错误状态通过 HTTP Status Code 表达 (4xx/5xx)，`200 OK` 仅代表业务成功。

| 错误类别 | HTTP Status | Error Code | 重试策略 | 幂等性 (X-Idempotency-Key) |
| :--- | :--- | :--- | :--- | :--- |
| **Service Unavailable** | 502/503/504 | `E-500x` | **Allowed**. Attempts ≤ 3 AND **RetryBudget ≤ 2.0s** (Backoff 0.2/0.5/1.0). | **Required** |
| **LLM Rate Limit** | 429 | `E-4029` | **Allowed**. Max 1 (Switch Model). | **Required** |
| **Schema Violation** | 502 | `E-5001` | **Allowed**. Max 1 (Temp=0). *视为下游服务(LLM)故障*。**Log Required**: `prompt_version`, `model_id`, `validator_errors`. | **Required** |
| **Semantic Mismatch** | 422 | `E-4071` | **Forbidden**. 业务无法处理。 | N/A |
| **Bad Request** | 400 | `E-4000` | **Forbidden**. 参数错误。 | N/A |
| **Signature Fail** | 401 | `E-4001` | **Forbidden**. 触发 **REBIND**。 | N/A |

### 2.1.1 Error Code Registry (规范表)
| Code | Name | Category | HTTP Status | Description |
|------|------|----------|------------|-------------|
| E-4001 | SignatureFail | Authentication | 401 | Invalid or expired request signature |
| E-4002 | ReplayDetected | Security | 409 | Nonce already used (replay attack) |
| E-4029 | RateLimited | Throttling | 429 | Request rejected by rate limiting or quota policy |
| E-4071 | SemanticMismatch | Contract | 422 | Intent is valid but slots or semantics are invalid |
| E-5001 | SchemaViolation | Server | 502 | LLM produced invalid response (Downstream Failure) |
| E-5004 | LLMTimeout | Downstream | 504 | LLM did not respond within SLA |

Classification rules:
- 4xxx: client, security, or throttling
- 5xxx: server or downstream failure

### 2.2 重试叠加与自动回滚

1.  **Retry Priority (叠加规则)**:
    *   **Global Retry Budget**: **Max 2.0s** (Strict). 任何重试若会导致总耗时超过预算，必须立即终止并返回。
    *   **Backoff Strategy**: **0.2s, 0.5s, 1.0s** (Mobile Optimized). 避免在坏网络下拖爆 9.5s SLA。

2.  **Auto Rollback (自动回滚)**:
    *   **Trigger**: 当 `json_schema_error_rate` (500/E-5001) 在 1分钟内 > **5%**。
    *   **Action**: LLM Gateway 自动降级至上一个 `Verified` Prompt 版本 (Verified = **Passed CI/CD Evaluation Gate**)。

### 2.3 Idempotency Strategy

To prevent duplicated processing caused by client retries, network reconnections, or gateway retries, the system enforces strict idempotency control.

#### 2.3.1 Idempotency Key Generation
The client MUST generate one `X-Idempotency-Key` per user intent attempt.

- A "user intent attempt" is defined as one continuous interaction from:
  `LongPress_Start` → `Listening` → `Thinking` → (success or error)

- All retries, reconnects, and retransmissions for the same intent MUST reuse the same `X-Idempotency-Key`.
- A new `LongPress_Start` MUST generate a new `X-Idempotency-Key`.

This guarantees that retries are safely deduplicated.

#### 2.3.2 Deduplication Storage
The Orchestrator MUST maintain an idempotency cache:

*   **Key**: `device_id` + `X-Idempotency-Key`
*   **Value**: Cached final API response (success or error)
*   **Storage**: Redis or equivalent in-memory store
*   **TTL**: 10 minutes

#### 2.3.3 Request Handling Behavior

When a request arrives:

| Condition | Behavior |
|--------|--------|
| Key not found | Process normally and store result |
| Key exists | Return cached response immediately (no reprocessing) |

This guarantees:
- No duplicate LLM calls
- No duplicated user actions
- Safe retries across flaky networks

### 2.4 Timeout Configuration & Cancellation (Timeout 预算)

基于 SRS 9.5s 的 SLA，各层级超时配置如下：

1.  **Component Timeouts**:
    *   **API Gateway**: **9.0s** (Overall). 预留 0.5s 给 Client 渲染与网络波动。
    *   **Orchestrator**: **8.5s**.
    *   **LLM Gateway**: **5.0s**. (严格限制推理耗时).

2.  **Cancellation & Abort Semantics**:
    *   When the client cancels a request (e.g., user taps outside or closes the overlay), the server MUST stop all downstream processing.
    *   **Implementation requirements**:
        *   If the LLM provider supports request cancellation:
            *   The LLM Gateway MUST invoke the provider’s cancel API immediately.
        *   If the provider does NOT support cancellation:
            *   The LLM Gateway MUST stop reading further tokens
            *   The Orchestrator MUST abort all downstream execution
            *   The request MUST be marked as "canceled"
            *   The response MUST NOT be sent back to the client
            *   The request MUST be excluded from UI updates and state transitions
        *   **Cost accounting**: Such requests MUST be recorded as "canceled but billable" for cost analytics.

---

## 3. 安全架构 (Security Architecture)

### 3.1 Device Binding & Key Lifecycle

本系统无用户账号体系，采用**设备绑定**模式。

1.  **Device Start (Bind)**:
    *   调用 `/api/v1/device/bind`。
    *   **传输安全**: `Secret_Key` 通过 **TLS 加密通道** 下发，客户端开启证书钉扎 (Certificate Pinning)。
    *   **存储安全**: 存入 Android Keystore，标记为不可导出。

2.  **Usage (Sign)**:
    *   **Request Signature Canonicalization**:
        *   To guarantee deterministic signature verification, all requests MUST use canonicalized payloads.
        *   **For JSON requests** (e.g. Action callbacks):
            *   Body MUST be Canonical JSON (UTF-8, Sorted keys, No whitespace).
            *   Header `X-Body-SHA256` = SHA-256(Canonical_JSON_Bytes).
        *   **For multipart/form-data** (e.g. /intent/process with audio):
            *   Header `X-Body-SHA256` = SHA-256(Raw_Audio_Bytes).
        *   **For pure text input** (e.g. /intent/process fallback):
            *   Header `X-Body-SHA256` = SHA-256(UTF-8(text_input)).
    *   **Signature Construction**:
        *   Input: `X-Body-SHA256 + "\n" + X-Timestamp + "\n" + X-Nonce`
        *   `Sign = HMAC-SHA256(Input, Secret_Key)`

### 3.2 Replay Protection (Server-side Requirements)

为了防御重放攻击，服务端 (**Gateway** 或 **IAM 插件**) 必须强制执行以下校验：

1.  **Unique Check**:
    *   基于 `Nonce` + `Device_Id` 组合进行去重校验。

2.  **Time Window**:
    *   **TTL**: **60s** (需严格与签名 Timestamp 有效窗口一致)。

3.  **Error Handling**:
    *   若检测到 Nonce 重复，立即拒绝。
    *   **Status**: `409 Conflict` (Rationale: Auth success but state conflict)
    *   **Error Code**: `E-4002` (REPLAY_DETECTED)

---

## 4. 可观测性 (Observability)

### 4.1 Client RUM Metrics (Real User Monitoring)

由于服务端延迟不等于用户感知延迟，必须以客户端埋点为准。

*   **`client_e2e_latency`**: `Render_Complete` - `Listening_End` (SRS SLA **9.5s** 基准)。
*   **`client_network_overhead`**: `Request_Start` - `Response_End` (纯网络耗时)。
*   **`client_render_cost`**: Flutter 渲染耗时 (首帧)。
*   **Correlation**: 客户端将 `X-Trace-Id` 放入埋点日志，便于服务端关联分析。

---

## 5. 接口与契约 (API & Error Handling)

### 5.1 Device Bind API

*   **Endpoint**: `POST /api/v1/device/bind`
*   **Desc**: 设备首次激活或 Rebind 时调用。
    *   **Device Fingerprint**:
        *   Definition: `SHA-256(android_id + app_install_id + server_salt_version)`
        *   Properties: Salt is rotated periodically. Stable per app install.
        *   Privacy: Used ONLY for security/binding. Never for analytics/tracking.
    *   **Request**:
        ```json
        {
          "device_fingerprint": "hash_value_example",
          "os": "Android 12"
        }
        ```
*   **Response (200 OK)**:
    ```json
    {
      "device_id": "uuid_v4",
      "secret_key": "base64_random_32bytes",
      "server_time": 1709999999
    }
    ```
    *   **Security Note**:
        *   The returned `secret_key` is used only for request signing within this application instance.
        *   It is stored in Android Keystore and never exposed to other apps.
        *   *For production, consider short-lived session keys or server-side rotation.*

### 5.2 Process Intent API

*   **Endpoint**: `POST /api/v1/intent/process`
*   **Headers**: 
    *   `X-Device-Id`, `X-Signature`, `X-Idempotency-Key` (Required).
    *   `X-Mock-Scenario` (Optional, for Demo).
*   **Response (200 OK)**:
    ```json
    {
      "intent_id": "uuid_v4",
      "category": "SERVICE",
      "ui_schema_version": "1.0",
      "slots": { ... },
      "ui_payload": { ... }
    }
    ```
    *   **Note**: `ui_payload` is the concrete GenUI widget tree instance, NOT the schema definition.
*   **Validation**:
    *   **UI Schema Validation Responsibility**:
        *   The **LLM Gateway** is the single authority responsible for validating all GenUI JSON against the official UI Schema.
        *   **Responsibilities**:
            *   Validate JSON immediately after LLM generation.
            *   Produce `validator_errors` when validation fails.
            *   Reject invalid payloads before they reach the Orchestrator.
        *   The **Orchestrator**:
            *   MUST NOT perform schema parsing.
            *   MAY use validation results for policy decisions (e.g., auto-rollback, alerting).

### 5.3 Action Execute API (VNext)

*   **Endpoint**: `POST /api/v1/action/execute`
*   **Desc**: 处理 ActionList 或 Card 上的交互。
*   **Headers**: `X-Device-Id`, `X-Signature`, `X-Idempotency-Key` (Required).
*   **Body**:
    ```json
    { "action_id": "act_submit", "params": { ... } }
    ```
    *   **Client Routing Logic**:
        *   **Deep Link Strategy**: 若 `action_type == DEEP_LINK`，客户端**直接拦截并跳转**（如打开滴滴），仅异步上报埋点，**不阻塞 UI**。
        *   **Server Execute**: 仅当 `action_type == API_CALL`（如发送邮件）时，才调用本接口阻塞执行。

### 5.4 Error Contract (Status != 200)

```json
{
  "error_code": "E-5004",
  "message": "LLM inference timeout",
  "trace_id": "trace_xyz",
  "action": "RETRY | REBIND | TOAST | NONE",
  "user_tip": "服务开了小差，请稍后再试"
}
```
