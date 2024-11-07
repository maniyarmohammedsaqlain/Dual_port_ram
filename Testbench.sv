interface ramint;
  logic [7:0] data_a, data_b;
  logic [5:0] addr_a, addr_b;
  logic we_a, we_b; //write enable for Port A and Port B
  logic clk; //clk
  logic[7:0] q_a, q_b; //output data at Port A and Port B
endinterface

class transaction;
  rand bit[7:0] data_a, data_b;
  rand bit[5:0] addr_a, addr_b;
  rand bit we_a, we_b;
  bit[7:0] q_a, q_b;

  constraint data {
    we_a dist {0 := 30, 1 := 70};
    we_b dist {0 := 50, 1 := 50};
  }

  function void display(string name,bit clk=0);
    $display(" %t [%s] Value of data_a is %d data_b is %d addr_a is %d addr_b is %d we_a is %d we_b is %d q_a is %d and q_b is %d clk is %d",$time, name, data_a, data_b, addr_a, addr_b, we_a, we_b,q_a,q_b,clk);
  endfunction
endclass

class generator;
  transaction trans;
  mailbox gen2drv;
  event done;
  int count;

  function new(mailbox gen2drv);
    this.gen2drv = gen2drv;
  endfunction

  task run();
    begin
      repeat(count) begin
        trans = new();
        trans.randomize();
        trans.display("GEN");
        gen2drv.put(trans);
        #10;
      end
    end
  endtask
endclass

class driver;
  transaction trans;
  mailbox gen2drv;
  virtual ramint inf;
  event done;
  function new(mailbox gen2drv, virtual ramint inf, event done);
    this.gen2drv = gen2drv;
    this.inf=inf;
    this.done=done;
  endfunction
  
  task run();
    forever begin
      trans = new();
      gen2drv.get(trans);
      inf.data_a <= trans.data_a;
      inf.data_b <= trans.data_b;
      inf.we_a <= trans.we_a;
      inf.we_b <= trans.we_b;
      inf.addr_a <= trans.addr_a;
      inf.addr_b <= trans.addr_b;
      trans.display("DRV",inf.clk);
      #1;
      ->done;
      #10;
    end
  endtask
endclass

class monitor;
  transaction trans;
  mailbox mon2scb;
  virtual ramint inf;
  event done;

  function new(mailbox mon2scb, virtual ramint inf, event done);
    this.mon2scb = mon2scb;
    this.inf = inf;
    this.done = done;
  endfunction  

  task run();
    forever begin
      @(done); 
      trans = new();
      trans.data_a = inf.data_a;
      trans.data_b = inf.data_b;
      trans.addr_a = inf.addr_a;
      trans.addr_b = inf.addr_b;
      trans.we_a = inf.we_a;
      trans.we_b = inf.we_b;
      trans.q_a = inf.q_a;
      trans.q_b = inf.q_b;
      trans.display("MON",inf.clk);
      mon2scb.put(trans);
      
      #10;
    end
  endtask
endclass


class scoreboard;
  transaction trans;
  mailbox mon2scb;
  virtual ramint inf;
  bit[7:0]ram[63:0];
  
  function new(mailbox mon2scb,virtual ramint inf);
    this.mon2scb=mon2scb;
    this.inf=inf;
  endfunction
  
  task run();
    forever
      begin
        trans=new();
        mon2scb.get(trans);
        trans.display("SCO",inf.clk);
        $display("------------------------------------------------------------------------------------------------------------------------------------------------------------");
        if(trans.we_a)
          begin
            ram[trans.addr_a]=trans.data_a;
          end
        if(trans.we_b)
          begin
            ram[trans.addr_b]=trans.data_b;
          end
        
        if (!trans.we_a && trans.q_a != ram[trans.addr_a]) 
          begin
            $error("Mismatch on Port A at time %0t: Expected %0d, got %0d",$time, ram[trans.addr_a],trans.q_a);
          end 
        else if (trans.we_a==1 && trans.q_a == ram[trans.addr_a]) 
          begin
            $display("PASS on Port A at %0t: Expected %0d, got %0d", $time, ram[trans.addr_a], trans.q_a);
          end
        if (!trans.we_b && trans.q_b != ram[trans.addr_b]) begin
          $error("Mismatch on Port B at time %0t: Expected %0d, got %0d", $time, ram[trans.addr_b], trans.q_b);
        end 
        else if (trans.we_b==1 && trans.q_b == ram[trans.addr_b]) 
          begin
            $display("PASS on Port B at %0t: Expected %0d, got %0d", $time, ram[trans.addr_b], trans.q_b);
          end
      end
  endtask
endclass         
  
class environment;
  mailbox gen2drv;
  mailbox mon2scb;
  transaction trans;
  generator gen;
  driver drv;
  monitor mon;
  scoreboard scb;
  event done;
  
  function new(virtual ramint inf);
    gen2drv=new();
    mon2scb=new();
    gen=new(gen2drv);
    gen.count=10;
    drv=new(gen2drv,inf,done);
    mon=new(mon2scb,inf,done);
    scb=new(mon2scb,inf);
  endfunction
  task run();
    fork
      gen.run();
      drv.run();
      mon.run();
      scb.run();
    join
  endtask
endclass

module tb;
  ramint inf();
  environment env;
  dual_port_ram mem (
    .data_a(inf.data_a),
    .data_b(inf.data_b),
    .addr_a(inf.addr_a),
    .addr_b(inf.addr_b),
    .we_a(inf.we_a),
    .we_b(inf.we_b),
    .clk(inf.clk),
    .q_a(inf.q_a),
    .q_b(inf.q_b)
  );
  initial begin
    inf.clk = 1;
  end
  always 
    #10 inf.clk = ~inf.clk;
  initial begin
    env = new(inf);
    env.run();
  end
  initial begin
    #200; 
    $finish;
  end
endmodule
