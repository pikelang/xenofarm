// Xenofarm Python Garbage collector

inherit "../../gc_latest_by_system.pike";

string out_dir     = "/lysator/www/projects/xenofarm/python/export";  
string result_dir  = "/lysator/www/projects/xenofarm/python/files";

int gc_poll        = 60*60*2;
int dists_left     = 10;
int results_left   = 2;

