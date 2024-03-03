import micros
import macros, strutils


template write(arg: untyped) =
  result.add newCall("add", newIdentNode("result"), arg)

template writeLit(args: varargs[string, `$`]) =
  write newStrLitNode(args.join)

proc htmlInner(x: NimNode, indent = 0, stringProc = false): NimNode {.compiletime.} =
  result = newStmtList()
  
  x.expectKind nnkStmtList
  let spaces = repeat(' ', indent)
  for y in x:
    if stringProc:  # Handle evaluating strings in curly braces
      result.add quote do:
        result.add `y`
      continue
    case y.kind
    of nnkCurly: # try to evaluate things in curly braces
      let b = y[0]
      var s = newStmtList()
      s.add quote do:
        `b`
      result.add htmlInner(s, indent + 2, true)
    of nnkCaseStmt: # Transform Case statements into If/elif/else
      var toCheck = y[0]
      var branches = y[1..^1]
      var newIfs: seq[(NimNode, NimNode)]
      for branch in branches: # Every of
        for j in 0 ..< branch.len - 1: # Handle all cases from one of
          let ncond = condition(elifBranch(newCall("==", toCheck, branch[j]), htmlInner(branch[^1], indent + 2)))
          let newBranch = (ncond, htmlInner(branch[^1], indent + 2))
          newIfs.add newBranch        
      result.add newIfStmt(newIfs) 
      if branches[^1].kind == nnkElse: # Append the else branch
        result.add htmlInner(branches[^1][0], indent + 2)
    of nnkIfStmt: # Traverse If statements.
      var newIfs: seq[(NimNode, NimNode)]
      for k in y: # Every if/elif/else
        for j in 0 ..< k.len - 1:  # handle all and/or as well
          let ncond = k[j]
          let nbranch = (ncond, htmlInner(k[^1], indent + 2))
          newIfs.add nbranch
      result.add newIfStmt(newIfs)
      if y[^1].kind == nnkElse: # Append the else branch
        result.add htmlInner(y[^1][0], indent + 2)
    # This is where we handle creating HTML tags
    of nnkCall, nnkCommand: 
      var tag = y[0]
      let otag = tag
      tag.expectKind nnkIdent
      if $tag == "divv": tag = ident("div")
      if y.len > 2:
        writeLit spaces, "<", tag, " "
        for i, n in y:
          if n.kind == nnkExprEqExpr:
            if n[1].kind == nnkCurly:
              writeLit $n[0], "=\""
              write n[1][0]
              writeLit "\" "
            else:
              writeLit $n[0], "=\"", $n[1], "\" "
          elif n.kind == nnkStrLit:
            if $n != $otag:
              writeLit $n, " "
            writeLit $n, " "
        writeLit ">\n"
        if y[^1].kind == nnkStmtList:
          result.add htmlInner(y[^1], indent + 2)
        writeLit spaces, "</", tag, ">\n"
      elif y.len == 2:
        tag.expectKind nnkIdent
        # Handle tags without nesting, but with params
        if y[1].kind == nnkExprEqExpr:
          var n = y[1]
          writeLit spaces, "<", tag, " "
          if n[1].kind == nnkCurly:
            writeLit $n[0], "=\""
            write n[1][0]
            writeLit "\" "
          else:
            writeLit $y[1][0], "=", $y[1][1]
          writeLit ">\n"
        # elif y[1].kind == nnkIdent:
        #   writeLit $y[1], " "
        else:
          writeLit spaces, "<", tag, ">\n"
          # Recurse over child          
          result.add htmlInner(y[1], indent + 2)
          writeLit spaces, "</", tag, ">\n"
      else:
        writeLit spaces, "<", tag, " "
        for i, n in y:
          if n.kind == nnkExprEqExpr:
            writeLit $n[0], "=\"", $n[1], "\" "
          elif n.kind == nnkStrLit or n.kind == nnkIdent:
            if $n != $otag:
              writeLit $n, " "
        writeLit ">\n"

    else: # Write str lits
      writeLit spaces
      write y
      writeLit "\n"

macro htmlTemplate*(procDef: untyped): untyped =
  procDef.expectKind nnkProcDef

  echo procDef.treeRepr
  # Same name as specified
  let name = procDef[0]

  # Return type: string
  var params = @[newIdentNode("string")]
  # Same parameters as specified
  for i in 1..<procDef[3].len:
    params.add procDef[3][i]

  var body = newStmtList()
  # result = ""
  body.add newAssignment(newIdentNode("result"),
    newStrLitNode(""))
  # Recurse over DSL definition
  body.add htmlInner(procDef[6])

  # Return a new proc
  result = newStmtList(newProc(name, params, body))
