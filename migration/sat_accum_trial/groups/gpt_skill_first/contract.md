# sat_accum_stream numeric and cycle contract

Frozen from the task at 2026-11-02 10:40:16 UTC. No unresolved functional assumptions.

* s_x: signed 16-bit integer, [-32768,32767]. s_k: signed 8-bit Q1.7 (sign included), raw code [-128,127], real coefficient code/128.
* p = x*k: exact signed integer product, range [-4194176,4194304], fitting 24 signed bits.
* r = sign(p)*floor((abs(p)+64)/128), zero maps to zero. Halfway cases round away from zero. Range [-32767,32768]; r needs 17 signed bits.
* a starts at zero and changes only on input acceptance: a_next = min(32767,max(-32768,a+r)). Saturate after every accepted input; there is no hidden unsaturated state. y publishes a_next.
* clk rising edge; rst is active high synchronous reset. A reset edge clears a, y, valid and cancels any pending output. No input is accepted while rst is high.
* s_ready = !rst && (!m_valid || m_ready), continuously. Inputs accepted on s_valid && s_ready at the rising edge.
* Output before the edge is consumed on m_valid && m_ready, unless reset cancels it. If the same edge also accepts input, m_y is replaced with the new accumulation and m_valid remains asserted after the edge.
* If no input is accepted, a and y retain their values. If a pending output is consumed without replacement, valid clears. Backpressure holds valid/y, including when source inputs change.
* The output register is visible immediately after an accepting edge. No extra pipeline stage and no combinational m_y bypass. Capacity is one pending result; accumulator state survives output consumption.
* m_y remains unchanged even when valid is zero unless input is accepted or reset is sampled. Reset assertion between clock edges immediately disables s_ready but cannot asynchronously clear registered y/valid.

Hand calculations / boundaries:
- (x,k)=(1,63),(1,64),(1,65) give r=0,1,1; negative x gives 0,-1,-1.
- (1,-64) gives -1; (-1,-64) gives +1.
- (-32768,-128) gives r=+32768. From a=-1 the new value is 32767; from a=0 it saturates at 32767.
- (32767,-128) gives -32767. At a=-1 the new value is -32768.
- a=32767; then r=+1,+1,-1 must give 32767,32767,32766.
- a=-32768; then r=-1,-1,+1 must give -32768,-32768,-32767.

Test plan: hand vectors, all coefficient codes against boundary x, complete x range against k=-128,-1,127 with opposite-sign two-unit seed to expose the full increment instead of hiding rounding under saturation, saturation and recovery sequences, zero increments, input bubbles, long/random backpressure, simultaneous consumption/replacement, reset of held results, reset with s_valid and m_ready high, nonedge reset effects, deterministic random cycles (seed 0x51A7C0DE), final drain. All cycle comparisons exact; missing/extra cycles or completion marker fail validation. Python divmod integer arithmetic is the independent reference; it does not copy RTL bit operations. Small rational checks and multiplication identity validate the reference itself.

Simulation scope: functional RTL only. No synthesis, place/route, board, timing closure or CDC claims. No IP instantiated.

