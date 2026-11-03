现在调整分工，停止为同一批代码重复新建测试台。由GPT/执行侧跑Vivado，你作为另一个模型专门复审实际锁频补丁；不要继续此前累加器或全目录审查。
本轮只读以下三份文件：
1. E:/Codex/FPGA/workspace/report_targeted_revision_20261102/project_cross_review/inputs/rtl/laser/auto_lock_fsm.v（实际旧程序）
2. E:/Codex/FPGA/workspace/report_targeted_revision_20261102/project_cross_review/candidate/rtl/auto_lock_fsm.v（隔离修复候选）
3. E:/Codex/FPGA/workspace/report_targeted_revision_20261102/project_cross_review/inputs/project_contract.md（要求）
请不要读GPT评审结论或实际回归日志，不改任何文件，不新建仿真平台，不需要输出文件。直接在当前回复给出有证据的定向复审结果，建议3分钟内。
背景：旧代码在SWEEP_AVG最后一个采样点更新scan_min/max/min_code的同时做扫描结束判定，非阻塞赋值在同一个沿后才生效。候选意图把当前平均值纳入边界、对比度和半高值判断。
检查：候选是否确实解决末点成为新最小值时的误捕获；末点成为新最大值时是否一致；符号、位宽、初始极值、更新时刻是否产生新问题；是否误改FIND/反馈阶段或接口时序。对每条结论给文件位置及一个具体输入/时序例子。可以同意，也可以提出异议，不能仅复述上述意图。
输出依次为：复审结论；主要依据；可以交给执行侧复现的输入序列或断言；建议保留的回归项。尚未实际运行就标为静态推导，不能声称仿真通过。最终是否采纳由实际程序验收决定。
