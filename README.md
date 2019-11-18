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
- `--dstdir:DIR`  
  Set destination directory path (default: ".")  
- `--tmpdir:DIR`  
  Set temporary directory path (default: "/tmp")  
- `-o:FILE`, `--output:FILE`
  Set output filename (Please don't contain "/")
  If you set `-s` or `--split` option, this option will be ignored.
- `-s`, `--split`  
  Split by programs  
- `--margin:INT`  
  Set split margin seconds (default: 0)  
- `-w`, `--wraparound`  
  Avoid PCR/PTS/DTS wrap-around problem  
- `-p`, `--progress`  
  Show progress  
  If you set this option, PCR/PTS/DTS will be modified based on 01:00:00.
- `-v`, `--version`  
  Write tsreducer's version
- `-h`, `--help`  
  Show help

## Example

- The simple example is:
  ```
  $ ls ./ts
  input.m2ts
  $ tsreducer --dstdir:./ts -p ./ts/input.m2ts
  ```

  The result will be:
  ```
  Read: 511.3 MB/sec [  1.5 GB] / Write: 300.8 MB/sec [940.0 MB]
  $ ls ./ts
  input.m2ts input.reduced.m2ts
  ```

- If you want to set output filename:
  ```
  $ ls ./ts
  input.m2ts
  $ tsreducer --dstdir:./ts -o:output.m2ts -p ./ts/input.m2ts
  ```

  The result will be:
  ```
  Read: 511.3 MB/sec [  1.5 GB] / Write: 300.8 MB/sec [940.0 MB]
  $ ls ./ts
  input.m2ts output.m2ts
  ```

- If you want to split by programs:
  ```
  $ ls ./ts
  input.m2ts
  $ tsreducer --dstdir:./ts -s -p ./ts/input.m2ts
  ```

  The result will be:
  ```
  Read: 511.3 MB/sec [  1.5 GB] / Write: 300.8 MB/sec [940.0 MB]
  $ ls ./ts
  input.m2ts program1.m2ts program2.m2ts program3.m2ts
  ```
