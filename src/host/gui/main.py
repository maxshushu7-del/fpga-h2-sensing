# -*- coding: utf-8 -*-
"""V6-look FPGA H2 dashboard: live UDP reception, no generated telemetry."""
from __future__ import annotations
import csv
import math
import time
from collections import deque
from datetime import datetime
from pathlib import Path

import numpy as np
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from matplotlib import rcParams
from matplotlib.figure import Figure
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg

BASE = Path(__file__).resolve().parent
C = dict(bg='#07101e', bar='#0b1527', card='#101e31', edge='#243750', grid='#263a52',
         text='#f2f8ff', muted='#90a7c5', cyan='#42d8f6', blue='#5f94fc',
         green='#3be0ad', amber='#ffd27c', pink='#f67aa7', input='#172840', red='#ff7b7b')
FS_HZ = 250_000_000
FFT_POINTS = 4096
BASELINE_MHZ = 1.0
rcParams['font.sans-serif'] = ['Microsoft YaHei', 'Noto Sans CJK JP', 'Noto Sans CJK SC', 'SimHei', 'DejaVu Sans']
rcParams['axes.unicode_minus'] = False


def box(parent, bg=None, **kw):
    return tk.Frame(parent, bg=bg or C['bg'], **kw)


def label(parent, s, size=10, color='text', bold=False, **kw):
    return tk.Label(parent, text=s, bg=parent.cget('bg'), fg=C.get(color, color),
                    font=('Microsoft YaHei', size, 'bold' if bold else 'normal'), **kw)


def button(parent, title, command, primary=False):
    return tk.Button(parent, text=title, command=command, font=('Microsoft YaHei', 9, 'bold'),
                     bg=C['cyan'] if primary else C['input'],
                     fg=C['bg'] if primary else C['text'],
                     activebackground=C['blue'], activeforeground=C['text'],
                     bd=0, relief='flat', padx=12, pady=9, cursor='hand2')


def plot_area(parent, heading, ylabel, xlabel, color, tag=''):
    panel = box(parent, C['card'], highlightthickness=1, highlightbackground=C['edge'])
    header = box(panel, C['card']); header.pack(fill='x', padx=15, pady=(11, 1))
    label(header, heading, 10, bold=True).pack(side='left')
    label(header, tag, 8, 'muted').pack(side='right')
    fig = Figure(figsize=(6, 2.2), dpi=100, facecolor=C['card'])
    ax = fig.add_subplot(111)
    ax.set_facecolor(C['card'])
    for spine in ax.spines.values(): spine.set_color(C['edge'])
    ax.grid(True, color=C['grid'], alpha=.6, linewidth=.65)
    ax.tick_params(colors=C['muted'], labelsize=8, length=0, pad=5)
    ax.set_xlabel(xlabel, fontsize=8, color=C['muted'], labelpad=5)
    ax.set_ylabel(ylabel, fontsize=8, color=C['muted'], labelpad=6)
    fig.subplots_adjust(left=.105, right=.985, top=.96, bottom=.24)
    line, = ax.plot([], [], color=C[color], lw=1.45)
    canvas = FigureCanvasTkAgg(fig, master=panel)
    canvas.get_tk_widget().pack(fill='both', expand=True, padx=(7, 7), pady=(2, 6))
    return panel, ax, line, canvas


def metric(parent, title, unit, color, col):
    p=box(parent,C['card'],highlightthickness=1, highlightbackground=C['edge'])
    p.grid(row=0, column=col, sticky='nsew', padx=4, pady=4)
    label(p,title,9,'muted').pack(anchor='w',padx=14,pady=(10,0))
    line=box(p,C['card']); line.pack(anchor='w',fill='x',padx=14,pady=(2,12))
    var=tk.StringVar(value='—')
    tk.Label(line,textvariable=var,font=('Segoe UI',21,'bold'),fg=C[color],bg=C['card']).pack(side='left')
    var.unit=tk.StringVar(value=unit)
    tk.Label(line,textvariable=var.unit,font=('Microsoft YaHei',9),fg=C['muted'],bg=C['card']).pack(side='left',padx=7,pady=(8,0))
    return var


class Calibration:
    def __init__(self):
        with (BASE/'hydrogen_calibration.csv').open(encoding='utf-8-sig',newline='') as f:
            rows=list(csv.DictReader(f))
        self.c = np.array([float(r['concentration_ppm']) for r in rows])
        self.shift = np.array([float(r['shift_MHz']) for r in rows])
        assert len(rows)==28 and np.all(np.diff(self.c)>0) and np.all(np.diff(self.shift)>0)
    def at(self, concentration):
        if concentration <= self.c[0]:
            return 0.0 if concentration <= 0 else float(self.shift[0]*concentration/self.c[0])
        val=float(np.clip(concentration,self.c[0],153000.))
        return float(np.interp(val,self.c,self.shift))
    def inverse(self, shift):
        if not np.isfinite(shift) or shift > self.at(153000): return None
        if shift < self.shift[0]: return 0.0 if shift<=0 else None
        return float(np.interp(shift,self.shift,self.c))

    def shift_for_ppm(self, concentrations):
        """Piecewise-linear interpolation of the supplied calibration anchors."""
        concentration=np.asarray(concentrations,dtype=float)
        safe=np.maximum(concentration,0.0)
        main=np.interp(safe,self.c,self.shift)
        return np.where(safe<=self.c[0],self.shift[0]*safe/self.c[0],main)

    def ppm_for_shift(self, shifts):
        """Inverse used for the bottom plot's calibrated nonlinear y axis."""
        v=np.asarray(shifts,dtype=float)
        safe=np.maximum(v,0.)
        main=np.interp(safe,self.shift,self.c)
        return np.where(safe<=self.shift[0],self.c[0]*safe/self.shift[0],main)


from udp_live import UDPListener, LiveModel

class App:
    def __init__(self):
        self.cal=Calibration()
        self.model=LiveModel(self.cal)
        self.receiver=UDPListener()
        self.bind_host="0.0.0.0"
        self.bind_port=5001
        self.root=tk.Tk()
        self.root.title('H₂ SENSING | 01 激光锁定监测 · UDP ONLY')
        self.root.geometry('1250x900+30+30')
        self.root.minsize(930,680)
        self.root.configure(bg=C['bg'])
        self.root.protocol('WM_DELETE_WINDOW',self.close)
        self.beat=None
        self.last_real=time.monotonic()
        self.port_text=tk.StringVar(value=str(self.bind_port))
        self.ip_text=tk.StringVar(value=self.bind_host)
        self.baseline_text=tk.StringVar(value="1.000000")
        self._lock_ui()
        self._beat_ui()
        self._options_ui()
        # Open the lock window first; switch to the second workspace via navigation.
        self.beat.withdraw()
        self.receiver.start(self.bind_host,self.bind_port)
        self.root.after(60,self.loop)
        self.root.after(240,self.refresh_lock)
        self.root.after(340,self.refresh_beat)

    def header(self, win, glyph, title, subtitle, navtext, nav):
        bar=box(win,C['bar']);bar.pack(fill='x')
        inside=box(bar,C['bar']);inside.pack(fill='x',padx=24,pady=13)
        label(inside,glyph,23,'cyan',True).pack(side='left',padx=(0,13))
        left=box(inside,C['bar']);left.pack(side='left')
        label(left,title,17,bold=True).pack(anchor='w')
        label(left,subtitle,9,'muted').pack(anchor='w')
        button(inside,navtext,nav).pack(side='right')

    def control_bar(self, parent):
        ctrl=box(parent);ctrl.pack(fill='x',padx=23,pady=10)
        label(ctrl,'UDP 实时数据接收  /  激光锁定状态  /  ADC 拍频测量  /  温度监测',9,'muted').pack(side='left',padx=(0,18))
        button(ctrl,'网络设置',self.show_options).pack(side='right',padx=(7,0))

    def metric_strip(self,win,config):
        strip=box(win);strip.pack(fill='x',padx=19,pady=(5,7))
        for i in range(len(config)):strip.columnconfigure(i,weight=1)
        return [metric(strip,*item,col=i) for i,item in enumerate(config)]

    def _lock_ui(self):
        r=self.root
        self.header(r,'⌁','激光扫描与反馈锁定','DA 输出  ·  PD 响应  ·  误差闭环  |  WINDOW 01',
                    '打开拍频检测 ↗',self.show_beat)
        self.control_bar(r)
        self.da_metric,self.pd_metric,self.error_metric,self.state_metric=self.metric_strip(r,[
            ('DA 输出','—','amber'),('PD 输出','V','blue'),('锁定误差','—','cyan'),('锁定状态','','green')])
        statusbox=box(r,C['card']);statusbox.pack(fill='x',padx=24,pady=(1,4))
        self.event_var=tk.StringVar(value='UDP 监听中，等待 FPGA 数据')
        tk.Label(statusbox,textvariable=self.event_var,bg=C['card'],fg=C['muted'],
                 font=('Microsoft YaHei',10),anchor='w').pack(fill='x',padx=12,pady=7)
        foot=box(r,C['bar']);foot.pack(side='bottom',fill='x')
        label(foot,'FPGA DIGITAL LASER CONTROL',8,'muted').pack(side='right',padx=23,pady=10)
        charts=box(r); charts.pack(fill='both',expand=True,padx=24,pady=(3,13))
        charts.rowconfigure(0,weight=1);charts.rowconfigure(1,weight=1);charts.rowconfigure(2,weight=1)
        charts.columnconfigure(0,weight=1)
        self.lock_plots=[]
        for i,(title,ylabel,color) in enumerate([
            ('DAC OUTPUT / DA 扫描与反馈输出','DA (code)','amber'),
            ('PHOTODETECTOR / PD 响应','PD (V)','blue'),
            ('LOCK ERROR / 锁定误差','误差 (code)','cyan')]):
            p,ax,line,canvas=plot_area(charts,title,ylabel,'时间 (s)',color,'最近 48 s')
            p.grid(row=i,column=0,sticky='nsew',pady=4)
            self.lock_plots.append((ax,line,canvas))
            if i==2:
                ax.axhline(0,color=C['muted'],lw=1.0,ls='--',alpha=.75)
                self.feedback_line,=ax.plot([],[],color=C['green'],lw=1.9,alpha=.96,
                                            label='平滑反馈误差')
                ax.legend(loc='upper right',fontsize=8,facecolor=C['card'],
                          edgecolor=C['edge'],labelcolor=C['text'])

    def _beat_ui(self):
        w=tk.Toplevel(self.root)
        self.beat=w
        w.title('H₂ SENSING | 02 拍频信号与浓度 · UDP ONLY')
        w.geometry('1260x970+260+45')
        w.minsize(1020,760)
        w.configure(bg=C['bg'])
        w.protocol('WM_DELETE_WINDOW',w.withdraw)
        self.header(w,'◈','拍频解调与氢气浓度检测',
                    'TIME DOMAIN  ·  FFT  ·  H₂ RESPONSE   |   WINDOW 02',
                    '返回锁定监测 ↗',self.show_lock)
        (self.freq_metric,self.shift_metric,self.con_metric,self.temperature_metric,
         self.readiness_metric)=self.metric_strip(w,[
            ('测得拍频','MHz','cyan'),('相对基准频移 Δf','MHz','blue'),
            ('氢气浓度 H₂','ppm','green'),('当前温度','°C','amber'),
            ('系统状态','','green')])
        top=box(w);top.pack(fill='both',expand=True,padx=20,pady=(1,7))
        top.columnconfigure(0,weight=1);top.columnconfigure(1,weight=1);top.rowconfigure(0,weight=1)
        self.pwave,self.axwave,self.lwave,self.cwave=plot_area(top,'拍频信号 · 时域','ADC code','时间 (μs)','cyan','UDP ADC')
        self.pwave.grid(row=0,column=0,sticky='nsew',padx=4)
        self.pfft,self.axfft,self.lfft,self.cfft=plot_area(top,'FFT · 频域','幅度 (dBFS)','频率 (MHz)','blue','接收采样块后计算')
        self.pfft.grid(row=0,column=1,sticky='nsew',padx=4)
        self.peakline=self.axfft.axvline(0,color=C['amber'],lw=1,ls='--',alpha=.85)
        bottom=box(w);bottom.pack(fill='both',expand=True,padx=20,pady=(0,11))
        bottom.columnconfigure(0,weight=7);bottom.columnconfigure(1,weight=3);bottom.rowconfigure(0,weight=1)
        # Native ttk notebooks can render bright OS-themed tabs on Windows.
        # Use ordinary tkinter controls so the selected and unselected tabs
        # have the same navy background as the oscilloscope panels.
        self.data_tabs=box(bottom,C['bg'])
        self.data_tabs.grid(row=0,column=0,sticky='nsew',padx=4)
        tabhead=box(self.data_tabs,C['bg'])
        tabhead.pack(fill='x',pady=(0,5))
        self.data_tab_buttons={}
        for key,title in [('response','气体响应过程'),('calibration','浓度标定曲线')]:
            b=tk.Label(tabhead,text=title,font=('Microsoft YaHei',10,'bold'),bd=0,
                        padx=17,pady=8,cursor='hand2',
                        bg=C['input'],fg=C['muted'])
            b.bind('<Button-1>',lambda e,name=key:self.select_data_tab(name))
            b.pack(side='left',padx=(0,4))
            self.data_tab_buttons[key]=b
        dynamic_tab=box(self.data_tabs,C['bg'])
        calibration_tab=box(self.data_tabs,C['bg'])
        self.data_tab_frames={'response':dynamic_tab,'calibration':calibration_tab}
        self.active_data_tab=None
        dynamic_tab.rowconfigure(0,weight=1)
        dynamic_tab.rowconfigure(1,weight=1)
        dynamic_tab.columnconfigure(0,weight=1)
        (self.pshift,self.axshift,self.lshift,self.cshift)=plot_area(
            dynamic_tab,'拍频频移随时间变化','Δf (MHz)','监测时间 (s)','blue','UDP 采样时间轴')
        self.pshift.grid(row=0,column=0,sticky='nsew',pady=(1,3))
        (self.pconc,self.axconc,self.lconc,self.cconc)=plot_area(
            dynamic_tab,'氢气浓度随时间变化','浓度 (ppm)','监测时间 (s)','green','非线性浓度刻度')
        self.pconc.grid(row=1,column=0,sticky='nsew',pady=(3,1))
        # Each row's curve is driven by the SAME source frequency sample.
        # The physical conversion is nonlinear; a calibrated functional axis
        # puts equal changes in source shift at equal vertical positions while
        # correctly labelling the bottom plot in ppm, not linear ppm.
        for ax in (self.axshift,self.axconc):
            ax.set_xlim(0,220)
        self.axshift.set_ylim(0,35)
        self.axconc.set_yscale('function',functions=(self.cal.shift_for_ppm,
                                                    self.cal.ppm_for_shift))
        self.axconc.set_ylim(0,float(self.cal.ppm_for_shift(35)))
        self.axconc.set_yticks([0,1,10,50,100])
        self.axconc.set_yticklabels(['0','1','10','50','100'])
        self.spot_shift,=self.axshift.plot([],[],marker='o',color=C['amber'],markersize=5,ls='none')
        self.spot_conc,=self.axconc.plot([],[],marker='o',color=C['amber'],markersize=5,ls='none')
        self.cursor_shift=self.axshift.axvline(0,color=C['amber'],lw=.8,ls='--',alpha=.6)
        self.cursor_conc=self.axconc.axvline(0,color=C['amber'],lw=.8,ls='--',alpha=.6)
        self.readout_shift=self.axshift.text(.98,.95,'',transform=self.axshift.transAxes,
            ha='right',va='top',fontsize=9,color=C['amber'],
            bbox=dict(facecolor=C['card'],edgecolor='none',alpha=.85))
        self.readout_conc=self.axconc.text(.98,.95,'',transform=self.axconc.transAxes,
            ha='right',va='top',fontsize=9,color=C['amber'],
            bbox=dict(facecolor=C['card'],edgecolor='none',alpha=.85))
        calibration_tab.rowconfigure(0,weight=1)
        calibration_tab.columnconfigure(0,weight=1)
        self.pcal,self.axcal,self.lcal,self.ccal=plot_area(
            calibration_tab,'氢气浓度—拍频频移标定曲线','频移 Δf (MHz)','浓度 (ppm)','blue','28 个标定点')
        self.pcal.grid(row=0,column=0,sticky='nsew')
        self.axcal.set_xscale('log')
        self.axcal.set_yscale('linear')
        self.lcal.set_data(self.cal.c,self.cal.shift)
        self.axcal.scatter(self.cal.c,self.cal.shift,s=10,color=C['cyan'],alpha=.8)
        self.axcal.set_xlim(.0008,600000)
        self.axcal.set_ylim(-20,950)
        self.marker,=self.axcal.plot([],[],marker='o',markersize=10,color=C['green'],lw=0,zorder=8)
        self.ccal.draw_idle()
        self.select_data_tab('response')
        right=box(bottom,C['card'],highlightthickness=1,highlightbackground=C['edge'])
        right.grid(row=0,column=1,sticky='nsew',padx=4)
        label(right,'检测与事件记录',11,bold=True).pack(anchor='w',padx=15,pady=(16,7))
        self.baseline_label_var=tk.StringVar(value='基准频率  1.000000 MHz')
        tk.Label(right,textvariable=self.baseline_label_var,bg=C['card'],fg=C['muted'],
                 font=('Microsoft YaHei',9)).pack(anchor='w',padx=15,pady=4)
        label(right,'标定点  28 组',10,'muted').pack(anchor='w',padx=15,pady=4)
        label(right,'有效范围  0.001～153000 ppm',9,'muted').pack(anchor='w',padx=15,pady=4)
        temp_panel=box(right,C['input'])
        temp_panel.pack(fill='x',padx=13,pady=(9,3))
        label(temp_panel,'温度控制 / PID',10,bold=True).pack(anchor='w',padx=10,pady=(9,2))
        self.temp_detail=tk.StringVar(value='目标 — °C  ·  加热 —%')
        tk.Label(temp_panel,textvariable=self.temp_detail,bg=C['input'],fg=C['cyan'],
                 font=('Microsoft YaHei',9),anchor='w').pack(fill='x',padx=10,pady=(0,9))
        self.event2=tk.StringVar(value='UDP 监听中，等待 FPGA 数据')
        label(right,'最新事件',9,'muted').pack(anchor='w',padx=15,pady=(17,4))
        tk.Label(right,textvariable=self.event2,bg=C['card'],fg=C['cyan'],wraplength=260,
                 justify='left',font=('Microsoft YaHei',10,'bold')).pack(fill='x',padx=15,pady=6)
        footer=box(w,C['bar']);footer.pack(side='bottom',fill='x')
        label(footer,'FPGA H₂ SENSOR',8,'muted').pack(side='right',padx=23,pady=10)

    def select_data_tab(self,name):
        if self.active_data_tab==name:return
        if self.active_data_tab is not None:
            self.data_tab_frames[self.active_data_tab].pack_forget()
        self.active_data_tab=name
        for key,btn in self.data_tab_buttons.items():
            selected=(key==name)
            btn.configure(bg=C['card'] if selected else C['input'],
                          fg=C['cyan'] if selected else C['muted'])
        self.data_tab_frames[name].pack(fill='both',expand=True)
        self.root.after(120,self.ccal.draw_idle if name=='calibration' else self.cshift.draw_idle)

    def _options_ui(self):
        w=tk.Toplevel(self.root)
        self.options=w
        w.title('H₂ SENSING | UDP 网络配置')
        w.geometry('540x435+160+130')
        w.minsize(480,390)
        w.configure(bg=C['bg'])
        w.protocol('WM_DELETE_WINDOW',w.withdraw)
        self.header(w,'⚙','网络与数据选项','UDP 监听 · 基准频率 · 导出', '关闭窗口',w.withdraw)
        area=box(w);area.pack(fill='both',expand=True,padx=22,pady=14)
        card=box(area,C['card'],highlightthickness=1,highlightbackground=C['edge']);card.pack(fill='both',expand=True)
        r=box(card,C['card']);r.pack(fill='x',padx=16,pady=(20,9))
        label(r,'监听地址',10,'muted').pack(side='left')
        tk.Entry(r,textvariable=self.ip_text,width=16,bg=C['input'],fg=C['text'],bd=0,
                 insertbackground=C['text'],font=('Consolas',11)).pack(side='left',padx=(10,15),ipady=8)
        label(r,'UDP 端口',10,'muted').pack(side='left')
        tk.Entry(r,textvariable=self.port_text,width=7,bg=C['input'],fg=C['text'],bd=0,
                 insertbackground=C['text'],font=('Consolas',11)).pack(side='left',padx=(10,0),ipady=8)
        r2=box(card,C['card']);r2.pack(fill='x',padx=16,pady=9)
        label(r2,'拍频基准 (MHz)',10,'muted').pack(side='left')
        tk.Entry(r2,textvariable=self.baseline_text,width=13,bg=C['input'],fg=C['text'],bd=0,
                 insertbackground=C['text'],font=('Consolas',11)).pack(side='left',padx=(10,0),ipady=8)
        r3=box(card,C['card']);r3.pack(fill='x',padx=16,pady=9)
        button(r3,'应用 / 重新监听',self.rebind_udp,primary=True).pack(side='left',padx=(0,10))
        button(r3,'清空图表',self.clear_data).pack(side='left',padx=(0,10))
        button(r3,'导出 CSV',self.export).pack(side='left')
        self.options_state=tk.StringVar(value='')
        tk.Label(card,textvariable=self.options_state,bg=C['card'],fg=C['cyan'],
                 font=('Microsoft YaHei',9),anchor='w',justify='left',wraplength=470).pack(fill='x',padx=17,pady=(15,5))
        label(card,'接收端不主动请求数据；UDP 没有连接握手。',9,'muted').pack(anchor='w',padx=17,pady=(0,8))
        label(card,'仅接收 FPGA 以太网发来的 UDP 数据，缺失字段显示 —。',9,'muted').pack(anchor='w',padx=17,pady=(0,15))
        w.withdraw()

    def show_options(self):
        self.options.deiconify();self.options.lift()

    def rebind_udp(self):
        try:
            host=self.ip_text.get().strip()
            if not host:raise ValueError('监听 IP 不可为空')
            port=int(self.port_text.get().strip())
            if not 1<=port<=65535:raise ValueError('端口必须在 1~65535')
            baseline=float(self.baseline_text.get())
            if not np.isfinite(baseline) or baseline<0:raise ValueError('基准频率必须大于等于0')
        except ValueError as exc:
            messagebox.showerror('配置错误',str(exc),parent=self.options);return
        # A new endpoint or baseline starts a new acquisition session.
        self.model.clear()
        self.model.baseline_mhz=baseline
        self.baseline_label_var.set(f'基准频率  {baseline:.6f} MHz')
        self.bind_host=host;self.bind_port=port
        ok=self.receiver.start(host,port)
        self.options_state.set('监听 %s:%d %s' %(host,port,'已启动' if ok else '启动失败'))
        if not ok:messagebox.showerror('监听失败',str(self.receiver.bind_error),parent=self.options)

    def clear_data(self):
        self.model.clear()

    def show_beat(self):
        self.beat.deiconify();self.beat.lift()

    def show_lock(self):
        self.beat.withdraw()
        self.root.deiconify();self.root.lift()

    def loop(self):
        now=time.monotonic()
        for typ,payload,rx,sender in self.receiver.drain():
            if typ=='packet':
                self.model.apply(payload,rx,sender)
            elif typ=='reject':
                self.model.last_error=payload
            elif typ=='error':
                self.model.network_status='监听失败：'+payload
        self.model.mark_stale(now)
        if hasattr(self,'options_state'):
            address='%s:%s'%(self.bind_host,self.bind_port)
            self.options_state.set('UDP %s  |  %s\n有效包 %d  拒绝 %d  丢弃 %d  来源 %s' %(
                address,self.model.network_status,self.receiver.datagrams,
                self.receiver.rejected,self.receiver.dropped,self.model.sender))
        self.root.after(70,self.loop)

    def refresh_lock(self):
        m=self.model
        valid=lambda v: bool(np.isfinite(v))
        self.da_metric.set(f'{m.da:.4f}' if valid(m.da) and m.da_unit=='V' else
                           f'{m.da:.0f}' if valid(m.da) else '—')
        self.da_metric.unit.set(m.da_unit if valid(m.da) else '')
        self.pd_metric.set(f'{m.pd:.4f}' if valid(m.pd) else '—')
        self.error_metric.set(f'{m.err:+.2f}' if valid(m.err) else '—')
        self.error_metric.unit.set(m.error_unit if valid(m.err) else '')
        self.state_metric.set(m.state if m.last_status is not None else '等待数据')
        self.event_var.set('%s  |  %s  |  最近来源：%s' % (m.network_status,m.event,m.sender))
        t,da,pd,err,_,_=m.snapshot()
        _,filtered=m.feedback_snapshot()
        if len(t)>=1:
            right=max(48.,t[-1]);left=max(0.,right-48.)
            for i,(ax,line,canvas) in enumerate(self.lock_plots):
                y=(da,pd,err)[i]
                line.set_data(t,y)
                if i==2:self.feedback_line.set_data(t,filtered)
                ax.set_xlim(left,right)
                if i==0:
                    ax.set_ylabel('DA (%s)'%m.da_unit,color=C['muted'],fontsize=8)
                    visible=y[(t>=left)&np.isfinite(y)]
                    if len(visible):
                        ymin,ymax=np.min(visible),np.max(visible)
                        pad=max(0.03 if m.da_unit=='V' else 100.,(ymax-ymin)*.25)
                        ax.set_ylim(ymin-pad,ymax+pad)
                elif i==1:
                    vv=y[(t>=left)&np.isfinite(y)]
                    if len(vv):
                        ymin,ymax=float(np.min(vv)),float(np.max(vv))
                        pad=max(.02,(ymax-ymin)*.2)
                        ax.set_ylim(ymin-pad,ymax+pad)
                else:
                    ax.set_ylabel('误差 (%s)'%m.error_unit,color=C['muted'],fontsize=8)
                    vv=y[np.isfinite(y)&(t>=left)]
                    extent=max(10.,min(30000.,np.percentile(abs(vv),99.5)*1.25)) if len(vv) else 60.
                    ax.set_ylim(-extent,extent)
                canvas.draw_idle()
        self.root.after(280,self.refresh_lock)

    def refresh_beat(self):
        m=self.model
        valid=np.isfinite(m.measured_freq)
        self.freq_metric.set(f'{m.measured_freq:,.4f}' if valid else '—')
        self.shift_metric.set(f'{m.current_shift_mhz:+,.4f}' if valid else '—')
        c=m.measured_conc
        self.con_metric.set(f'{c:,.3f}' if c is not None and np.isfinite(c) else '—')
        self.temperature_metric.set(f'{m.temperature_c:,.2f}' if np.isfinite(m.temperature_c) else '—')
        target=f'{m.temperature_target_c:.2f}' if np.isfinite(m.temperature_target_c) else '—'
        duty=f'{m.heater_duty_pct:.1f}' if np.isfinite(m.heater_duty_pct) else '—'
        source=m.temperature_source
        fault=' · 温度故障' if m.temperature_fault else ''
        self.temp_detail.set(f'{source} · 目标 {target} °C · 加热 {duty}%{fault}')
        self.readiness_metric.set(m.network_status if m.network_status!='正在接收 UDP 数据' else
                                  '稳定测频' if valid and m.locked else '接收中 / 待锁定')
        self.event2.set(m.event)
        a=m.beat_wave
        if len(a) and m.sample_rate_hz:
            x=np.arange(len(a))*1e6/m.sample_rate_hz
            self.lwave.set_data(x,a)
            self.axwave.set_xlim(0,max(3.,float(x[-1])))
            extent=max(9000.,np.max(np.abs(a))*1.2)
            self.axwave.set_ylim(-extent,extent)
        else:
            self.lwave.set_data([],[])
        self.cwave.draw_idle()
        if len(m.frequencies):
            self.lfft.set_data(m.frequencies,m.fft)
            self.axfft.set_xlim(0,max(125.,m.frequencies[-1]))
        else:self.lfft.set_data([],[])
        self.axfft.set_ylim(-110,5)
        self.peakline.set_xdata([m.measured_freq]*2 if valid else [0,0])
        self.cfft.draw_idle()
        if valid and c is not None and np.isfinite(c):
            self.marker.set_data([max(c,.001)],[m.current_shift_mhz])
        else:self.marker.set_data([],[])
        if m.response_elapsed_hist:
            elapsed=np.asarray(m.response_elapsed_hist,dtype=float)
            shifts=np.asarray(m.response_shift_hist,dtype=float)
            concentrations=np.asarray(m.response_conc_hist,dtype=float)
            right=max(220.,float(elapsed[-1]));left=max(0.,right-220.)
            for ax in (self.axshift,self.axconc):ax.set_xlim(left,right)
            vv=shifts[(elapsed>=left)&np.isfinite(shifts)]
            if len(vv):
                vmin,vmax=np.min(vv),np.max(vv)
                gap=max(0.3,(vmax-vmin)*.15)
                low=max(0.,float(vmin-gap));high=max(low+.4,float(vmax+gap))
                self.axshift.set_ylim(low,high)
                self.axconc.set_ylim(float(self.cal.ppm_for_shift(low)),float(self.cal.ppm_for_shift(high)))
                ticks=np.linspace(low,high,5)
                ppm_ticks=self.cal.ppm_for_shift(ticks)
                self.axconc.set_yticks(ppm_ticks)
                self.axconc.set_yticklabels([f'{v:.2f}' if v<10 else f'{v:.1f}' for v in ppm_ticks])
            visible=elapsed>=left
            self.lshift.set_data(elapsed[visible],shifts[visible])
            self.lconc.set_data(elapsed[visible],concentrations[visible])
            self.spot_shift.set_data([elapsed[-1]],[shifts[-1]])
            self.spot_conc.set_data([elapsed[-1]],[concentrations[-1]])
            for cursor in (self.cursor_shift,self.cursor_conc):
                cursor.set_xdata([elapsed[-1],elapsed[-1]])
            self.readout_shift.set_text('Δf  %.3f MHz'%shifts[-1] if np.isfinite(shifts[-1]) else '')
            self.readout_conc.set_text('浓度  %.3f ppm'%concentrations[-1] if np.isfinite(concentrations[-1]) else '')
        else:
            self.lshift.set_data([],[]);self.lconc.set_data([],[])
            self.spot_shift.set_data([],[]);self.spot_conc.set_data([],[])
            self.readout_shift.set_text('');self.readout_conc.set_text('')
        if self.active_data_tab=='response':
            self.cshift.draw_idle();self.cconc.draw_idle()
        else:self.ccal.draw_idle()
        self.root.after(420,self.refresh_beat)

    def export(self):
        filename=filedialog.asksaveasfilename(parent=self.options,title='导出 UDP 接收记录',
                defaultextension='.csv',filetypes=[('CSV','*.csv')],
                initialfile='H2_UDP_'+datetime.now().strftime('%Y%m%d_%H%M%S')+'.csv')
        if not filename:return
        with open(filename,'w',encoding='utf-8-sig',newline='') as f:
            wr=csv.writer(f)
            wr.writerow(['received_time_s','packet_type','lock_state','da_value',
                         'pd_v','error_value','beat_mhz','shift_mhz','hydrogen_ppm',
                         'temperature_c','heater_duty_pct','source'])
            for entry in self.model.audit:
                wr.writerow(list(entry)+['UDP_RECEIVED'])
        messagebox.showinfo('导出完成',f'已保存到：\n{filename}',parent=self.options)

    def close(self):
        self.receiver.stop()
        self.root.destroy()

    def run(self):
        self.root.mainloop()

if __name__=='__main__':
    App().run()
