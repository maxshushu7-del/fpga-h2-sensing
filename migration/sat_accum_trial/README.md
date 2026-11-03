# 累加器四条件试用材料

先读trial_results.md。groups中保存四份首次可验收RTL与共同验收结果；acceptance保留冻结程序和清单；original_failure_logs保留选取的原始失败日志。

复跑例子（Windows，已安装Vivado2024.1，输出需为新的空E盘目录）：

```powershell
& .\acceptance\run_candidate.ps1 -CandidateRtl .\groups\deepseek_ordinary_first\sat_accum_stream.sv -OutputDirectory E:\your_project\trial_replay -VivadoBin E:\Xilinx\Vivado\2024.1\bin
```

原始结果JSON中的绝对路径用于记录当时来源，随包对应文件可按groups和acceptance定位。候选原始自述保持原样，环境版本以实际命令为准；DeepSeek原报告的Python3.11已在总汇总纠正为3.12.14。普通与Skill两类的GPT提示词整理版见trial_prompts.md，不冒称由客户端导出的完整原始对话。
