# Hands-on practices always win!
## In this sample, we are going to explore 'sed' command and have some fun! I asked Gemeni to provide me with challenges with 'sed'. Here I'm going to share them with you
## Base Input for the file is : 

```text
101, John Doe, Software Engineer, $120000, Active
102, Jane Smith, Data Scientist, $135000, Active
103, Bob Johnson, DevOps Engineer, $115000, Inactive
104, Alice Williams, Product Manager, $130000, Active
# NOTE: Update next week
105, Charlie Brown, QA Engineer, $95000, Active
```
## Challenge 1 : 
### Change all instances of the word "Active" to "Current".
### Easy to catch ha ? :D 
```bash
sed 's/Active/Current/g' practice.txt
```

## Challenge 2 : 
### Delete the comment line (the line starting with #).
```bash
sed '/\#/d' practice.txt
```
### we used \ as escape charecter, because is # is special charecter and having meaning in Regex.
### d means delete.

## Challenge 3 : 
### Change "Active" to "Current", but only on the line for "Alice Williams" : 

```bash
sed '/Alice Williams/s/Active/Current/' practice.txt
```
## Challenge 4 : 
### Delete the very last line of the file completely : 

```bash
 sed -e '/\$/d' practice.txt
```

## Challenge 5 : 
## Swap the first name and last name for every person (e.g., change "John Doe" to "Doe John") : 
## Little bit tricky! 

```bash
sed -E 's/([A-Z][a-z]+) ([A-Z][a-z]+)/\2 \1/' practice.txt 
```
