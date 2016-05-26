cs344
=====

Introduction to Parallel Programming class code

# Building on OS X

These instructions are for OS X 10.9 "Mavericks".

* Step 1. Build and install OpenCV. The best way to do this is with
Homebrew. However, you must slightly alter the Homebrew OpenCV
installation; you must build it with libstdc++ (instead of the default
libc++) so that it will properly link against the nVidia CUDA dev kit. 
[This entry in the Udacity discussion forums](http://forums.udacity.com/questions/100132476/cuda-55-opencv-247-os-x-maverick-it-doesnt-work) describes exactly how to build a compatible OpenCV.

* Step 2. You can now create 10.9-compatible makefiles, which will allow you to
build and run your homework on your own machine:
```
mkdir build
cd build
cmake ..
make
```

----

### Problem Set 1  
Each row is block.
```c
const dim3 blockSize(numRows, 1, 1);  //TODO
const dim3 gridSize(numCols, 1, 1);  //TODO
```

----

### Problem Set 2
Tile Algorithm 

```c
#define O_TILE_WIDTH 8
#define BLOCK_WIDTH (O_TILE_WIDTH + 8)
...
const dim3 blockSize(BLOCK_WIDTH,BLOCK_WIDTH);
const dim3 gridSize(numCols/O_TILE_WIDTH+1, numRows/O_TILE_WIDTH+1, 1);
```

Only ***O_TILE_WIDTH*** \* ***O_TILE_WIDTH*** threads participate in calculating outputs,
and only safe threads participate in writing output.
```c
if( threadIdx.y < O_TILE_WIDTH && threadIdx.x < O_TILE_WIDTH && (row < numRows) && (col < numCols) ){
```
In ***gaussian_blur*** kernel function, I used shared memeory do get fast memeory access time.

