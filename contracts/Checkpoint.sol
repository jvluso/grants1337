pragma solidity ^0.4.24;

// Checkpoints allow you to update a value over time and find what the value was
// at a previous point. You can use it to find a value between two checkpoints.
// The base value must always be ascending.
library Checkpoint {
  struct Data { 
    Point[] checkpoints; 
  }

  struct Point{
    uint from;
    uint value;
  }

  function insert(Data storage self, uint from, uint value)
      public
  {
      require(self.checkpoints.length == 0 || self.checkpoints[self.checkpoints.length - 1].from< from);
      self.checkpoints.push(Point(from,value));
  }

  function getValueAt(Data storage self, uint at) constant public returns (uint) {
    if (self.checkpoints.length == 0) return 0;

    // Shortcut for the actual value
    if (at >= self.checkpoints[self.checkpoints.length-1].from)
      return self.checkpoints[self.checkpoints.length-1].value;
    if (at < self.checkpoints[0].from) return 0;

    // Binary search of the value in the array
    uint min = 0;
    uint max = self.checkpoints.length-1;
    while (max > min) {
      uint mid = (max + min + 1)/ 2;
      if (self.checkpoints[mid].from<=at) {
        min = mid;
      } else {
        max = mid-1;
      }
    }
    return self.checkpoints[min].value;
  }

  function getValueAfter(Data storage self, uint at) constant public returns (uint) {
    if (self.checkpoints.length == 0) return 0;

    // Shortcut for the actual value
    if (at >= self.checkpoints[self.checkpoints.length-1].from)
      return self.checkpoints[self.checkpoints.length-1].value;
    if (at < self.checkpoints[0].from) return 0;

    // Binary search of the value in the array
    uint min = 0;
    uint max = self.checkpoints.length-1;
    while (max > min) {
      uint mid = (max + min + 1)/ 2;
      if (self.checkpoints[mid].from<=at) {
        min = mid+1;
      } else {
        max = mid;
      }
    }
    return self.checkpoints[min].value;
  }
}
