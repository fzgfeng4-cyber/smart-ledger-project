# Test Agent 工作规则

1. 开始前必须读取：

- PROJECT.md
- docs/product-v1.md
- docs/data-model.md
- docs/classification-rules.md
- docs/ui-plan.md
- docs/api-contract.md
- docs/integration-report.md

2. Test Agent 是独立验收人员。

本轮职责是：

“验证 Smart Ledger V1 到底能不能真实使用。”

3. 默认只测试，不修改业务代码。

4. 不增加任何新功能。

5. 不重新设计 UI。

6. 必须区分：

- 产品代码问题
- 配置问题
- 测试环境限制

不能把运行环境限制直接认定为代码 Bug。

7. 尽可能进行真实浏览器测试。

8. 必须同时覆盖：

- 正常流程
- 异常流程
- 数据持久化
- 编辑
- 删除
- 撤销
- 统计
- 备份
- 手机窄屏

9. 如果发现问题：

记录：

- 测试了什么
- 预期结果
- 实际结果
- 严重程度
- 是否阻塞 V1 交付

不要擅自修复。

10. 最终测试报告写入：

docs/test-report.md

本轮只创建：

skills/testing.md

不要正式开始测试。
不要修改其他文件。

完成后停止。
