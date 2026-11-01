## A tiny go board: play the main line of a game, with captures, and return the final
## position. The twin of src/goboard.py; in the post it is the callback.

proc neighbours(p, size: int): seq[int] =
  let (x, y) = (p mod size, p div size)
  if x > 0: result.add p - 1
  if x < size - 1: result.add p + 1
  if y > 0: result.add p - size
  if y < size - 1: result.add p + size

proc group(board: string, p, size: int): (seq[int], bool) =
  ## The stones connected to `p`, and whether the group has a liberty.
  let color = board[p]
  var stack = @[p]
  var seen = @[p]
  var libs = false
  while stack.len > 0:
    let q = stack.pop
    for r in neighbours(q, size):
      if board[r] == '\0': libs = true
      elif board[r] == color and r notin seen:
        seen.add r
        stack.add r
  (seen, libs)

proc replay*(moves: string, size = 19): (string, int, int) =
  ## moves: two SGF letters per move ("aa" is the top-left point, "tt" a pass).
  ## Returns the board (size*size chars: '\0' empty, '\1' black, '\2' white) and the
  ## stones captured by Black and by White.
  var board = newString(size * size)
  var caps = [0, 0, 0]
  var color = '\1'
  var i = 0
  while i + 1 < moves.len:
    let (x, y) = (ord(moves[i]) - 97, ord(moves[i + 1]) - 97)
    if x in 0 ..< size and y in 0 ..< size:
      let p = y * size + x
      board[p] = color
      let other = if color == '\1': '\2' else: '\1'
      for q in neighbours(p, size):
        if board[q] == other:
          let (stones, libs) = group(board, q, size)
          if not libs:
            for g in stones: board[g] = '\0'
            caps[ord(color)] += stones.len
      let (own, libs) = group(board, p, size)
      if not libs:  # suicide: remove own group (allowed in some rules)
        for g in own: board[g] = '\0'
        caps[ord(other)] += own.len
    color = if color == '\1': '\2' else: '\1'
    i += 2
  (board, caps[1], caps[2])
