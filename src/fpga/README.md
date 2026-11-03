# 第四版集成FPGA工程

器件 `xcau15p-ffvb676-2-i`，工具Vivado 2024.1，顶层 `laser_lock_hw_udp_only_top`。

`rtl`为板级基线；`constraints`为引脚与时序；`coefficients`为窗/NCO等系数；`ip_templates`为FFT、ILA、VIO配置；`scripts/create_project.tcl`从这些文件创建工程，不依赖旧XPR或DCP。

从仓库根目录执行 `./build/scripts/create_project.ps1 -VivadoBin E:/Xilinx/Vivado/2024.1/bin`，打开生成的 `src/fpga/project/contest_all.xpr` 后运行综合与实现。详细步骤见[从零复现](../../report/reproduction.md)。

本次只修复创建入口中的无参数save_project错误；没有修改归档下载文件对应的控制RTL。温度联合演示对象是 `tec200_virtual_plant`，真实温度驱动接口单独核验。UDP仅发送状态快照，不接收上位机控制命令。

技能案例中的候选补丁不属于这里的已实现基线；其应用需单独验证、重新综合与上板。
