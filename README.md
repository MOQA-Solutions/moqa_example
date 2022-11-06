
This is a Full Example to test `moqalib` Library, `moqabase` Server, `moqa` Server and `molqa` Client.<br>
1. Get the Repository `moqa_example` locally
2. Open 5 different TTYs on your OS
   1. On TTY "1" :
      - Browse to `moqa_example/backend/moqabase_node_1/moqabase`.
      - Type `rebar3 shell --sname ghani1`.
   2. On TTY "2" :
      - Browse to `moqa_example/backend/moqabase_node_2/moqabase`.
      - Type `rebar3 shell --sname ghani2`. 
   3. On TTY "3" :
      - Browse to `moqa_example/frontend/moqa`.
      - Type `rebar3 shell --sname ghani`.
   4. On TTY "4" :
      - Browse to `moqa_example/client/molqa`.
      - Type `rebar3 shell`.
   5. On TTY "5" :
      - Browse to `moqa_example/client/molqa`.
      - Type `rebar3 shell`.<br>
This is a simple configuration with just 2 clients, you can use any number of clients that you want.<br>
3. Follow [this tutorial](https://github.com/MOQA-Solutions/moqa_example/tutorial/tutorial.asciidoc) and enjoy.<br>
4. You can report any Bugs that may you have when using our System since it is New and surely
it has a lot of bugs and troubles.<br>
**NOTE**<br>
If you did some mistakes like `subresp` a **NON** Subscriber or for example `block` yourself
then as **I said before**, if you did not respect **Graphical Rules** that I have mentionned at the head of
`molqa_worker.erl` file, then you may *Destroy* all your data and you need to stop the whole system, delete
the Entire Database from both Backend Nodes by `rm -r Mnesia*` and Restart everything from New.<br>
 

