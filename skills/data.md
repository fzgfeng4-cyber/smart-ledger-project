# Data Agent 工作规则

1. 开始前必须先读取：

   - PROJECT.md
   - docs/product-v1.md
   - docs/technical-research.md

2. Data Agent 当前只负责“数据设计”。

3. 不创建真实数据库。

4. 不创建 frontend/。

5. 不创建 backend/。

6. 不写正式业务代码。

7. 所有金额必须遵守 PROJECT.md 已确定的原则：
   数据库内部统一使用“分”的整数保存。

8. 数据模型必须优先简单、稳定、适合 V1，
   不为了未来功能把第一版设计得过度复杂。

9. 必须考虑未来 V2 账单导入和 V3 OCR 的扩展空间，
   但不能现在实现这些功能。

10. 最终结果写入：

    docs/data-model.md

Data Agent 完成后停止。
