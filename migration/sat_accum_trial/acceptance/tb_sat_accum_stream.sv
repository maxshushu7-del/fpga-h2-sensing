`timescale 1ns/1ps
module tb_sat_accum_stream;
  localparam integer SEED = 20261102;
  logic clk=0, rst=0, s_valid=0, m_ready=0;
  logic signed [15:0] s_x=0;
  logic signed [7:0] s_k=0;
  wire s_ready, m_valid;
  wire signed [15:0] m_y;
  sat_accum_stream dut(.*);
  always #5 clk=~clk;
  integer a=0, y=0, cycles=0, checks=0, active=1;
  bit valid=0, initialized=0;
  bit started[1:6], done[1:6], failed[1:6];
  integer class_checks[1:6];
  string names[1:6];
  string counterexample="";
  integer inputs=0, outputs=0, simultaneous=0, stalled=0, stall_run=0, max_stall=0, cancellations=0;
  integer unsigned rng=SEED;

  // Oracle uses signed integer multiplication, integer division, and conditions.
  // It does not use arithmetic shifts, product slices, or candidate RTL logic.
  function automatic integer increment(input integer x, input integer k);
    longint signed p, magnitude, quotient;
    begin
      p=longint'(x)*longint'(k);
      if(p<0) magnitude=-p; else magnitude=p;
      quotient=(magnitude+64)/128;
      if(p<0) increment=-quotient; else increment=quotient;
    end
  endfunction
  function automatic integer clamp(input integer old_a, input integer r);
    longint signed total;
    begin
      total=longint'(old_a)+longint'(r);
      if(total>32767) clamp=32767;
      else if(total< -32768) clamp=-32768;
      else clamp=total;
    end
  endfunction
  // Stable cross-simulator PRNG instead of simulator-dependent $urandom.
  function automatic integer unsigned random_word();
    begin rng=rng*32'd1664525+32'd1013904223; random_word=rng; end
  endfunction
  task automatic report(input bit pass);
    integer fd;
    string state;
    begin
      fd=$fopen("tb_result.json","w");
      if(fd==0) $fatal(1,"Cannot create tb_result.json");
      $fwrite(fd,"{\n\"schema\":1,\n\"status\":\"%s\",\n\"seed\":%0d,\n\"cycles\":%0d,\n\"signal_checks\":%0d,\n",pass?"PASS":"FAIL",SEED,cycles,checks);
      $fwrite(fd,"\"input_handshakes\":%0d,\n\"output_handshakes\":%0d,\n\"simultaneous_handshakes\":%0d,\n",inputs,outputs,simultaneous);
      $fwrite(fd,"\"stalled_cycles\":%0d,\n\"max_stall_run\":%0d,\n\"reset_cancellations\":%0d,\n",stalled,max_stall,cancellations);
      if(counterexample=="") $fwrite(fd,"\"first_counterexample\":null,\n");
      else $fwrite(fd,"\"first_counterexample\":\"%s\",\n",counterexample);
      $fwrite(fd,"\"categories\":[\n");
      for(integer j=1;j<=6;j=j+1) begin
        if(failed[j]) state="FAIL";
        else if(done[j]) state="PASS";
        else if(started[j]) state="INCOMPLETE";
        else state="NOT_RUN";
        $fwrite(fd,"{\"id\":%0d,\"name\":\"%s\",\"status\":\"%s\",\"signal_checks\":%0d}%s\n",j,names[j],state,class_checks[j],j<6?",":"");
        $display("SAT_ACCUM_CATEGORY id=%0d name=%s status=%s checks=%0d",j,names[j],state,class_checks[j]);
      end
      $fwrite(fd,"]\n}\n"); $fclose(fd);
      $display("SAT_ACCUM_ACCEPTANCE_COMPLETE status=%s seed=%0d cycles=%0d checks=%0d",pass?"PASS":"FAIL",SEED,cycles,checks);
    end
  endtask
  task automatic fail(input string phase, input string field_name, input string expected, input string actual);
    begin
      failed[active]=1;
      counterexample=$sformatf("cycle=%0d phase=%s class=%0d field=%s expected=%s actual=%s rst=%b s_valid=%b s_ready=%b s_x=%0d s_k=%0d m_ready=%b ref_a=%0d",cycles,phase,active,field_name,expected,actual,rst,s_valid,s_ready,$signed(s_x),$signed(s_k),m_ready,a);
      $display("SAT_ACCUM_FIRST_COUNTEREXAMPLE %s",counterexample);
      report(0); $fatal(1,"Acceptance mismatch");
    end
  endtask
  task automatic compare(input string phase);
    bit expected_ready;
    logic signed [15:0] expected_y;
    begin
      expected_ready=!rst&&(!valid||m_ready); expected_y=y;
      checks=checks+1; class_checks[active]=class_checks[active]+1;
      if(s_ready!==expected_ready) fail(phase,"s_ready",$sformatf("%b",expected_ready),$sformatf("%b",s_ready));
      checks=checks+1; class_checks[active]=class_checks[active]+1;
      if(m_valid!==valid) fail(phase,"m_valid",$sformatf("%b",valid),$sformatf("%b",m_valid));
      checks=checks+1; class_checks[active]=class_checks[active]+1;
      if(m_y!==expected_y) fail(phase,"m_y",$sformatf("%0d",expected_y),$sformatf("%0d",$signed(m_y)));
    end
  endtask
  task automatic step(input bit reset_i, input bit valid_i, input bit ready_i, input integer x_i, input integer k_i);
    bit accept, consume;
    begin
      @(negedge clk); rst=reset_i; s_valid=valid_i; m_ready=ready_i; s_x=x_i; s_k=k_i;
      #1; if(initialized) compare("before_edge");
      accept=!reset_i&&valid_i&&(!valid||ready_i);
      consume=!reset_i&&valid&&ready_i;
      @(posedge clk); cycles=cycles+1;
      if(reset_i) begin
        if(valid) cancellations=cancellations+1;
        a=0; y=0; valid=0; stall_run=0;
      end else begin
        if(valid&&!ready_i) begin
          stalled=stalled+1; stall_run=stall_run+1;
          if(stall_run>max_stall) max_stall=stall_run;
        end else stall_run=0;
        if(consume) outputs=outputs+1;
        if(accept&&consume) simultaneous=simultaneous+1;
        if(accept) begin inputs=inputs+1; a=clamp(a,increment(x_i,k_i)); y=a; valid=1; end
        else if(consume) valid=0;
      end
      initialized=1; #1; compare("after_edge");
    end
  endtask
  task automatic begin_class(input integer n);
    begin active=n; started[n]=1; end
  endtask
  integer xs[0:8], ks[0:6];
  integer x,k,base;
  integer unsigned rx,rk,rc;
  initial begin
    names[1]="sign_zero_extremes"; names[2]="rounding_half_neighbors";
    names[3]="saturation_hold_recovery"; names[4]="continuous_simultaneous_io";
    names[5]="long_backpressure_random"; names[6]="pending_reset_restart";
    for(integer j=1;j<=6;j=j+1) begin started[j]=0; done[j]=0; failed[j]=0; class_checks[j]=0; end
    xs[0]=-32768; xs[1]=-32767; xs[2]=-129; xs[3]=-1; xs[4]=0;
    xs[5]=1; xs[6]=127; xs[7]=32766; xs[8]=32767;
    ks[0]=-128; ks[1]=-127; ks[2]=-1; ks[3]=0; ks[4]=1; ks[5]=126; ks[6]=127;
    begin_class(1);
    step(1,1,1,-32768,-128); step(0,0,1,0,0);
    for(integer i=0;i<9;i=i+1) for(integer j=0;j<7;j=j+1) begin
      step(1,0,1,0,0); step(0,1,1,xs[i],ks[j]); step(0,0,1,0,0);
    end
    step(0,1,1,128,1); step(0,1,1,0,-128); step(0,1,1,-32768,0); done[1]=1;
    begin_class(2);
    for(integer b=0;b<11;b=b+1) begin
      if(b<9) base=b; else base=b+245;
      for(integer d=63;d<=65;d=d+1)
        for(integer sx=-1;sx<=1;sx=sx+2) for(integer sk=-1;sk<=1;sk=sk+2) begin
          step(1,0,1,0,0); step(0,1,1,sx*(base*128+d),sk); step(0,0,1,0,0);
        end
    end
    for(integer d=63;d<=65;d=d+1)
      for(integer sx=-1;sx<=1;sx=sx+2) for(integer sk=-3;sk<=3;sk=sk+6) begin
        step(1,0,1,0,0); step(0,1,1,sx*d,sk); step(0,0,1,0,0);
      end
    done[2]=1;
    begin_class(3); step(1,0,1,0,0);
    repeat(8) step(0,1,1,32767,127); repeat(4) step(0,1,1,64,1);
    step(0,1,1,-64,1); step(0,1,1,-32768,127);
    repeat(8) step(0,1,1,-32768,127); repeat(4) step(0,1,1,-64,1);
    step(0,1,1,64,1); step(0,1,1,32767,127);
    repeat(16) step(0,1,1,32767,127); repeat(16) step(0,1,1,-32768,127);
    repeat(16) step(0,1,1,32767,-128); repeat(16) step(0,1,1,-32768,-128);
    step(0,0,1,0,0); done[3]=1;
    begin_class(4); step(1,0,1,0,0);
    for(integer i=0;i<384;i=i+1) begin
      rx=random_word(); rk=random_word(); x=$signed(rx[15:0]); k=$signed(rk[23:16]); step(0,1,1,x,k);
    end
    repeat(4) step(0,0,1,32767,-128); done[4]=1;
    begin_class(5); step(1,0,0,0,0); step(0,1,0,128,1);
    for(integer i=0;i<128;i=i+1) begin
      rx=random_word(); rk=random_word(); x=$signed(rx[15:0]); k=$signed(rk[23:16]); step(0,1,0,x,k);
    end
    step(0,1,1,-64,1); repeat(80) step(0,0,0,-32768,-128); step(0,0,1,0,0);
    for(integer i=0;i<1024;i=i+1) begin
      rx=random_word(); rk=random_word(); rc=random_word(); x=$signed(rx[15:0]); k=$signed(rk[23:16]);
      step(0,rc[25:24]!=0,rc[17:16]==0,x,k);
    end
    repeat(4) step(0,0,1,0,0); done[5]=1;
    begin_class(6);
    for(integer i=0;i<4;i=i+1) begin
      step(1,0,1,0,0); step(0,1,0,-32768,-128); repeat(3) step(0,1,0,32767,127);
      step(1,1,i%2,-32768,127); step(1,1,1,32767,127); step(0,0,0,32767,127);
      step(0,1,0,-64,1); step(1,1,0,32767,127); step(0,1,0,64,1);
      step(0,1,1,128,1); step(0,0,1,0,0);
    end
    repeat(3) step(0,0,1,0,0); done[6]=1; report(1); $finish;
  end
  initial begin #1000000; fail("watchdog","completion","test_finished","simulation_timeout"); end
endmodule
