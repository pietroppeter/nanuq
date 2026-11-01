"""A tiny go board: play the main line of a game, with captures, and return the final
position. Pure Python on purpose: in the post it is the callback the Nim version beats."""

def replay(moves: bytes, size: int = 19):
    """moves: two SGF letters per move ("aa" is the top-left point, "tt" a pass).
    Returns (board, captured_by_black, captured_by_white); board is a bytes object of
    size*size cells: 0 empty, 1 black, 2 white."""
    board = bytearray(size * size)
    caps = [0, 0, 0]
    color = 1
    for i in range(0, len(moves) - 1, 2):
        x, y = moves[i] - 97, moves[i + 1] - 97
        if 0 <= x < size and 0 <= y < size:
            p = y * size + x
            board[p] = color
            other = 3 - color
            for q in _nbrs(p, size):
                if board[q] == other:
                    group, libs = _group(board, q, size)
                    if not libs:
                        for g in group: board[g] = 0
                        caps[color] += len(group)
            group, libs = _group(board, p, size)
            if not libs:  # suicide: remove own group (allowed in some rules)
                for g in group: board[g] = 0
                caps[other] += len(group)
        color = 3 - color
    return bytes(board), caps[1], caps[2]

def _nbrs(p, size):
    x, y = p % size, p // size
    if x > 0: yield p - 1
    if x < size - 1: yield p + 1
    if y > 0: yield p - size
    if y < size - 1: yield p + size

def _group(board, p, size):
    color = board[p]
    stack, seen, libs = [p], {p}, False
    while stack:
        q = stack.pop()
        for r in _nbrs(q, size):
            c = board[r]
            if c == 0: libs = True
            elif c == color and r not in seen:
                seen.add(r); stack.append(r)
    return seen, libs
