

# Compilation
Requires Nim to be installed. See https://nim-lang.org/

`nim c myqsub.nim`

# Usage
Place compiled executable in path.
See usage the following usage details by running `myqsub --help`

```
Qsub wrapper for the Phyletica Lab to more conveniently run jobs on Hopper. 

This wrapper will assign your job to either the general or gen28 queue based on  
  processor availability unless a specific queue is specified. If the requested 
  time limit is greater than 1 hour, the job will be run on a Phyletica node to 
  prevent it from being preempted.

Usage:
  Accepts any options for qsub in addition to the options below.
  
  myqsub [options] [qsub options] <bash script file or STDIN>

Options:
  --nodes <int>       Number of nodes requested [default: 1].
  --ppn <int>         Numer of processors per node requested [default: 1].
  --time <h:mm:ss>    Time limit requested, max is 90 days [default: 1:00:00].
  --mem <int><mb|gb>  Memory requested [default: not specified].
  --ssh               Use when submitting job from non-head node.
  --restrict          Run only on phyletica lab nodes, has no effect for jobs 
                        with walltimes longer than 1:00:00.
  --help, -h          Show this help menu.

Qsub Options:
  Accepts any valid qsub options except for: -l and -W

Source code at: https://github.com/kerrycobb/qsub-wrapper
```