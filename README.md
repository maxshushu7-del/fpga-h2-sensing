# FPGA-Based Adaptive High-Precision Hydrogen Sensing System

基于FPGA的自适应高精度氢气传感系统。系统围绕激光工作点锁定、拍频FFT测频、环境管理与集成三条链路，在同一片FPGA上组织采样、处理、保护和UDP遥测。

## 阅读入口

| 材料 | 入口 |
|---|---|
| 技术报告 PDF / Word | [PDF](report/design/design_report.pdf) · [Word](report/design/design_report.docx) |
| 海报与介绍PPT | [中文海报](report/poster/poster_zh.pptx) · [英文海报](report/poster/poster_en.pptx) · [介绍PPT](report/media/system_introduction.pptx) |
| 作品介绍视频 | [MP4](report/media/system_introduction.mp4) |
| 从零复现 | [工具、命令、IP、接收与上板步骤](report/reproduction.md) |
| 第四版 FPGA 源码 | [src/fpga](src/fpga/README.md) |
| 匹配的 UDP 图形上位机 | [安装与运行](src/host/gui/README.md) · [40字节协议](src/host/gui/protocol_v4.md) |
| 下载文件 | [同次bit/ltx](board/bitstream) |
| 资源、时序与构建记录 | [build/reports](build/reports) |
| 实验照片与测频读数 | [photos](board/photos) · [frequency observations](data/measured/README.md) |
| 大模型协作原记录 | [提示词、回复、反例、修改与回归](report/ai_collaboration/README.md) |
| 可复用 Skill | [三项技能与迁移验证](skill/README.md) |
| 提交要求对照 | [AMD条款](report/requirements.md) · [材料清单](report/submission_checklist.md) |

## 硬件与数据接口

- ALINX AXAU15；AMD Artix UltraScale+ `xcau15p-ffvb676-2-i`。
- ADC：AD9643，配置250 MSPS；DAC：AD9122。
- Vivado 2024.1；Python 3.9+、numpy、matplotlib、tkinter。
- 顶层 `laser_lock_hw_udp_only_top`。UDP从 `192.168.1.10:5000` 广播至 `192.168.1.255:5001`，只用于遥测，不承载实时闭环或下行控制。
- GUI直接解析V4的40字节 `FPGA` / `TEC2` 大端状态包。该报文不含完整ADC采样块或完整FFT频谱；扩展数据入口与遥测分别处理。

## 已归档的验证

最终联合工程的归档布局布线结果：17,867 LUT、20,200 FF、42.5 BRAM Tile、88 DSP，WNS +0.006 ns、WHS +0.010 ns。本次在新目录创建Vivado工程并生成FFT/ILA/VIO成功，接收器12项单元与本机UDP回环测试通过。[运行范围和日志](build/reports/release_validation.md)。

`data/measured`保留团队给出的信号源测频读数转录；`data/reference`保留实际RTL运行导出的频谱。光学记录、RTL模型及电子板测按各自条件解释。V4联合顶层的温度对象为数字热模型，报文保留来源标志。

## 快速开始

先按[从零复现](report/reproduction.md)准备工具。核对发布文件可在仓库根目录执行：

```powershell
python build/scripts/verify_manifest.py
```

FPGA源码保留归档bitstream对应RTL；Skill中的候选补丁独立存放，没有混入该板级基线。旧新快照用于复查具体缺陷和回归，不代表多份同时生效的主工程。

## 目录与许可

`src / sim / build / board / data / skill / report`为主目录；`migration`与`verification`保存Skill迁移案例及历史验证材料，保留其相对引用。仓库不包含Vivado安装文件、编译缓存或大型中间网表。

自编代码沿用[MIT](LICENSE)。AMD/Xilinx及其他第三方IP、生成文件的权利和使用条件见各自声明；本仓库MIT不改变其原许可。签字授权书由团队单独提交，不公开放入仓库。
