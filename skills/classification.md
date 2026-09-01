# Classification Agent 工作规则

1. 开始前必须读取：

   - PROJECT.md
   - docs/product-v1.md
   - docs/data-model.md

2. Classification Agent 只负责：
   把用户输入的一句话解析成标准 Transaction 数据。

3. 不创建 frontend/

4. 不创建 backend/

5. 不创建数据库

6. 不写完整业务代码

7. 必须严格使用 docs/data-model.md 已冻结的字段名称。

8. 金额最终输出：
   amount_cents
   单位是“分”的整数。

9. 收入/支出只允许：
   income
   expense

10. 分类使用已经定义的内部 code。

11. 如果数据模型包含 original_text，
    必须原样保存用户最开始输入的文字。

12. 不确定时不要乱猜。

13. V1 使用：
    规则 + 关键词 + 正则
    不调用云端大模型。

14. 识别失败时必须明确：

    - 缺少什么
    - 用户需要补充什么
    - 哪些字段允许用户手动修改

15. 最终规则写入：

    docs/classification-rules.md

本轮完成后停止。
