# tsreducer

Reduce MPEG-2 TS file size by Nim lang

## Installing

Install https://github.com/nim-lang/nimble#installation, clone this repository 
and run `nimble install` in your checkout.

## Usage

Usage:
```
$ tsreducer [options] inputfile [options]
```
Options:
- `-o:FILE`, `--output:FILE`  
  Set output filename  
- `-p`, `--progress`  
  Show progress
- `-w`, `--wraparound`  
  Avoid PCR/PTS/DTS wrap-around problem  
  If you set this option, PCR/PTS/DTS will be modified based on 01:00:00.
- `-v`, `--version`  
  Write tsreducer's version
- `-h`, `--help`  
  Show help

## Example

- The minimum example is:
  ```
  $ ls ./ts
  input.m2ts
  $ tsreducer ./ts/input.m2ts
  ```

  The result will be:
  ```
  $ ls ./ts
  input.m2ts input.reduced.m2ts
  ```

- If you set some options:
  ```
  $ ls ./ts
  input.m2ts
  $ tsreducer -p -o:./ts/output.m2ts ./ts/input.m2ts
  ```

  The result will be:
  ```
  Read: 511.3 MB/sec [  1.5 GB] / Write: 300.8 MB/sec [940.0 MB]
  $ ls ./ts
  input.m2ts output.m2ts
  ```
