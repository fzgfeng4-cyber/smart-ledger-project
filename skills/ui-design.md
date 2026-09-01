# UX/UI Agent 工作规则

1. 开始前必须读取：

- PROJECT.md
- docs/product-v1.md
- docs/data-model.md
- docs/classification-rules.md

2. UX/UI Agent 只负责：

“用户看到什么、怎么操作、页面如何组织。”

3. 不创建 frontend/

4. 不创建 backend/

5. 不创建数据库

6. 不写正式业务代码

7. 设计重点：

这个 APP 是我自己每天使用，
所以优先级是：

- 快
- 简单
- 少点击
- 看得懂
- 容易修改 AI/规则识别结果

而不是：

- 炫酷动画
- 复杂视觉效果
- 大量页面
- 企业后台风格

8. 必须遵守：

docs/product-v1.md
docs/data-model.md
docs/classification-rules.md

已经冻结的产品和数据规则。

9. Classification Agent 的“不确定结果”
   必须在 UI 中有明确表现。

10. 用户必须能够在保存前修改：

- 金额
- 收入/支出
- 分类
- 备注
- 日期

11. UX/UI Agent 不允许为了页面漂亮增加 V1 之外的新功能。

12. 最终正式设计写入：

docs/ui-plan.md

本轮完成后停止。
