import os, osproc, strutils, strformat, random, terminal

const 
  qsubPath = "/cm/shared/apps/torque/6.1.1.1.h3/bin/qsub"
  helpText = """
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
"""
type 
  QsubParser = ref object
    args: seq[TaintedString]
    pos: int

proc next(parser: var QsubParser): TaintedString = parser.args[parser.pos + 1]

proc getVal(parser: var QsubParser): TaintedString = 
  if not parser.next.startsWith('-'):
    result = parser.next
    parser.pos.inc # Move parser to next arg
  else:
    quit(&"Expected value but got flag {parser.next}")

proc isHourPlus(time: string): bool = 
  var split = time.split(':')
  if not split.len == 3:
    quit("--time value must follow pattern h:mm:ss")
  if parseInt(split[0]) > 1:
    result = true
  # if parse(time, "H:mm:ss").hour > 1:
      # result = true

proc getAvailThreads(queue: string , cpuNum: int, restrict: bool): int = 
  var 
    nodes: seq[string]
    cpuNum = int(cpuNum)
    usedThreads: int 
    availThreads = 0
  if restrict:
    if queue == "standard":
      nodes = @["node010", "node035", "node119", "node178", "node185"]
    elif queue == "standard28":
      nodes = @["node311", "node327", "node329", "node331", "node336"]
  else:
    if queue == "standard":
      nodes = execCmdEx("pbsnodes -l free :" & queue & " | awk '{print $1}'"
          )[0].strip.split(Newlines)
    elif queue == "standard28":
      nodes = execCmdEx("pbsnodes -l free :" & queue & " | awk '{print $1}'"
          )[0].strip.split(Newlines)
  for node in nodes:
    usedThreads = parseInt(execCmdEx("pbsnodes " & node & " | grep \"dedicated_threads\" | awk '{print $3}'")[0].strip)
    availThreads = cpuNum - usedThreads + availThreads 
  result = availThreads  

proc myqsub(parser: var QsubParser) = 
  var 
    cmd: seq[string]
    customCmds: seq[string]
    qsubCmds: seq[string]
    arg: string
    nodes = 1 
    ppn = 1 
    ssh = false
    restrict = false 
    queue = ""
    walltime = "1:00:00"
    mem = "250mb"
    
  # Parse command line arguments
  while parser.pos < parser.args.len:
    arg = parser.args[parser.pos] 
    case arg: 
      of "--time":
        walltime = parser.getVal 
      of "--nodes":
        nodes = parseInt(parser.getVal) 
      of "--ppn":
        ppn = parseInt(parser.getVal)
      of "--mem":
        mem = parser.getVal 
      of "-q":
        queue = parser.getVal
      of "--ssh":
        ssh = true
      of "--restrict":
        restrict = true 
      of "--help", "-h":
        quit(helpText, 0)
      else: # pass argument directly to qsub
        if not arg.startsWith('-') or parser.next.startsWith('-'): # pass only flag
          # TODO: Maybe should throw error if argument '-' is not last argument
          qsubCmds.add(arg)
        else: # pass flag and value directly to qsub
          qsubCmds.add(&"{arg} {parser.getVal}")
    parser.pos.inc # Move parser to next arg

  # Use ssh if submitting from compute node 
  if ssh:
    let user = getEnv("USER")
    cmd.add(&"ssh {user}@hopper.auburn.edu")

  # Resource commands 
  customCmds.add([
    &"-l nodes={nodes}:ppn={ppn}",
    &"-l walltime={walltime}"])
  if mem.len > 0:
    customCmds.add(&"-l mem={mem}")

  # Set queue and restrict to phyletica nodes if needed
  if queue.len > 0: # Use specified queue
    customCmds.add(&"-q {queue}")
    # if (walltime.isHourPlus or restrict) and queue in ["general", "gen28"]:
    customCmds.add("-W group_list=jro0014_lab")
    if queue == "general":
      customCmds.add("-W x=FLAGS:ADVRES:jro0014_lab")
    elif queue == "gen28":
      customCmds.add("-W x=FLAGS:ADVRES:jro0014_s28") 
  else: # Use queue with most availability
    if walltime.isHourPlus: # If walltime is > 1 hour restrict to phyletica nodes
      restrict = true
    # Get number of free nodes
    var
      generalThreadsAvail = getAvailThreads(queue="standard", cpuNum=20, 
          restrict=restrict) 
      gen28ThreadsAvail = getAvailThreads(queue="standard28", cpuNum=28, 
          restrict=restrict) 
    # Set the queue
    if generalThreadsAvail > gen28ThreadsAvail:
      queue = "general"
    elif generalThreadsAvail < gen28ThreadsAvail:
      queue = "gen28"
    else:
      randomize()
      let rand = rand(1.0)
      if restrict:
        if rand < 0.417: # 100 (general): 140 (gen28), see /tools/scripts/qinfo.sh
          queue = "general"
        else:
          queue = "gen28" 
      else:
        if rand < 0.287: # 55 nodes * 28 cores (gen28) : 191 * 20 core (general)
          queue = "q gen28"
        else:
          queue = "q general"      
    customCmds.add(&"-q {queue}")
    # Arguments for restricting to phyletica nodes
    if restrict:
      customCmds.add("-W group_list=jro0014_lab")
      if queue == "general":
        customCmds.add("-W x=FLAGS:ADVRES:jro0014_lab")
      elif queue == "gen28":
        customCmds.add("-W x=FLAGS:ADVRES:jro0014_s28") 

  # Pass stdin as script if exists
  if not isatty(stdin): 
    var stdinStr = readAll(stdin)
    stdinStr.stripLineEnd()
    qsubCmds.add(&"<<< \"{stdinStr}\"")

  # Execute script
  cmd.add(qsubPath)
  cmd.add(customCmds)
  cmd.add(qsubCmds)
  var joinedCmd = cmd.join(" \\\n  ")
  echo "Executing: \n", joinedCmd, "\n" 
  var shell = execShellCmd(joinedCmd)

when isMainModule:
  var parser = (QsubParser(args: commandLineParams()))
  myqsub(parser)
