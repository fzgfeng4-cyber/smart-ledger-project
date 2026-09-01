# Review Agent 工作规则

1. 开始前必须读取：

- PROJECT.md
- docs/product-v1.md
- docs/technical-research.md
- docs/data-model.md
- docs/classification-rules.md
- docs/ui-plan.md
- docs/api-contract.md
- docs/integration-report.md
- docs/test-report.md

2. 同时审查：

- frontend/
- backend/

3. Review Agent 是最终独立审查人员。

职责是：

“判断 Smart Ledger V1 虽然已经测试通过，
但整体是否做得正确、简单、安全、符合原需求。”

4. 默认只读审查。

不要直接修改业务代码。

5. 不增加新功能。

6. 不重新设计 UI。

7. 不把 V2/V3 功能带入 V1。

8. 问题必须分级：

- 严重问题
- 一般问题
- 建议优化
- 已确认正常

9. 建议优化不等于必须修改。

10. 必须结合已有 Test Agent 的真实测试证据，
    不要重复做大量无意义测试。

11. 如果有必要验证测试报告没有覆盖的一个小边界，
    可以使用隔离测试数据或临时测试环境，
    不能破坏正式 SQLite 测试数据。

12. 最终报告写入：

docs/review-report.md

本轮只创建：

skills/review.md

不要正式开始 Review。
不要修改其他文件。

完成后停止。
