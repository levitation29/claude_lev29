**My Claude.ai stuff**

do_acid will work with just command_2.notes or command_2_preferences.notes
but the full ACID protocol needs claude_acid_2.notes
I'm going to update the do_acid in command_2.notes to get claude_acid_2.notes from this repo if not findable in a current claude chat.
claude should be able to figure that out and the right raw.github url will be in the do_acid definition in command_2*

command_2_preferences.notes should always be just the stripped down (no comments) version of command_2.notes for pasting into user preferences

has efficient "Conventions" style of getting multiple behaviors with less language, plus nice iterate language
I may reduce these as I understand what I really ant


From your preferences (I copy/paste the contents of command_2_preferences.notes into my account preference text box)
every defined shortcut in command_2*

**Describe**

describe-behavior  
describe-structure  
describe-structure-deep  

**Plan**

plan-review-api    
plan-simplify-silent    
simplify-plan    
simplify-plan-deeper    
plan-score  

**Filesystem**

showskillfs  
showtranscriptfs  
showprojectfs  
showuserfs  
showmyfs  
mtime_output  
mtime_claude  
touch_start  
session_time  
touch_chat_start  
chat_time  
session_time_header  

**Output modifiers**

dont_narrate_fixes  
skip_post-round_summary  
no_fix_list  
showme  
showmeall  
jump-to-bottom  
cleanstop  

**Single-shot**

review  
linesme  
timeout_sleep_ints  
fiximportant  
sequential-fixes  
rewrite  
otf  
do_acid  

**Workers**

fix-silent  
fix-broad-silent  
fix-security-silent  
fix-perf-review-silent  
fix-api-review-silent  
md-update-silent  
schema-update-silent  
fix-rewrite-silent  
fix-rewrite-keepcomments-silent  

**Counters**

session_counts  
session_counts_header  
session_counts_resync T C  

**Pipeline families**

fix  
broad  
security  
perf_review  
api_review  
md_update  
schema  
