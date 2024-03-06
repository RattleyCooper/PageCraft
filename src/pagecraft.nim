import micros
import macros, strutils


template write(arg: untyped) =
  result.add newCall("add", newIdentNode("result"), arg)

template writeLit(args: varargs[string, `$`]) =
  write newStrLitNode(args.join)

proc htmlInner(x: NimNode, indent = 0, stringProc = false): NimNode {.compiletime.} =
  ## Patch the proc so it runs as PageCraft code.
  #

  proc innerNimCode(nn: NimNode, idn = 0): NimNode {.compileTime.} =    
    ## Recursively patch `nimcode` blocks so the AST
    ## handles the pagecraft dsl.
    #
    nn.expectKind nnkStmtList
    var r = newStmtList()
    for s in nn:
      case s.kind
      of nnkCall, nnkCommand:
        let cidn = s[0]
        if cidn.kind == nnkIdent and $cidn == "pagecraft":
          r.add htmlInner(s[1], idn + 2)
        else:
          r.add quote do:
            `s`
      of nnkForStmt:
        var newFor = newStmtList()
        newFor.add innerNimCode(s[^1], idn)
        # newFor.add innerNimCode(stmts, idn + 2)
        r.add nnkForStmt.newTree(
          s[0], s[1], newFor
        )
      of nnkWhileStmt:
        var newWhile = newStmtList()
        newWhile = innerNimCode(s[^1], idn)
        r.add nnkWhileStmt.newTree(
          s[0], newWhile
        )
      of nnkCaseStmt:
        var newCase = nnkCaseStmt.newTree()
        var caseIdent = s[0]
        newCase.add caseIdent
        for branch in s[1..^1]:
          var ofStmts = newStmtList()
          case branch.kind
          of nnkOfBranch:
            ofStmts.add innerNimCode(branch[^1], idn)
            var newBranch = nnkOfBranch.newTree()
            newBranch.add branch[0]
            newBranch.add ofStmts
            newCase.add newBranch
          of nnkElse:
            ofStmts.add innerNimCode(branch[^1], idn)
            var newBranch = nnkElse.newTree()
            newBranch.add ofStmts
            newCase.add newBranch
          else:
            continue

        r.add quote do:
          `newCase`
      of nnkTryStmt:
        var newTry = nnkTryStmt.newTree()
        var tryStmts = innerNimCode(s[0], idn)
        newTry.add tryStmts
        for branch in s[1..^1]:
          var excStmts = newStmtList()
          case branch.kind
          of nnkExceptBranch:
            excStmts.add innerNimCode(branch[^1], idn)
            var newBranch = nnkExceptBranch.newTree()
            if branch.len > 1:
              for idnt in branch:
                if idnt.kind == nnkIdent:
                  newBranch.add idnt
            newBranch.add excStmts
            newTry.add newBranch
          of nnkElse:
            excStmts.add innerNimCode(branch[^1], idn)
            var newBranch = nnkElse.newTree()
            newBranch.add excStmts
            newTry.add newBranch
          else:
            continue
        r.add quote do:
          `newTry`
      of nnkIfStmt:
        var newIf = nnkIfStmt.newTree()
        for branch in s:
          var ifsStmts = newStmtList()
          var newCond: NimNode
          var isElse = false
          case branch.kind
          of nnkElifBranch:
            ifsStmts.add innerNimCode(branch[^1], idn)
            newCond = branch[0]
          of nnkElse:
            ifsStmts.add innerNimCode(branch[^1], idn)
          else:
            continue
          if isElse:
            var newBranch = nnkElse.newTree()
            newBranch.add ifsStmts
            newIf.add newBranch
          else:
            var newBranch = nnkElifBranch.newTree()
            newBranch.add newCond
            newBranch.add ifsStmts
            newIf.add newBranch
        r.add quote do:
          `newIf`
      else:
        r.add quote do:
          `s`
    r

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
      var addSpace = true
      tag.expectKind nnkIdent

      if $tag == "divv": tag = ident("div")
      if y.len > 2:
        if y[1].kind == nnkIdent and $y[1] == "pcInline":
          addSpace = false
        if addSpace:
          writeLit spaces, "<", tag, " "
        else:
          writeLit "<", tag, " "
        for i, n in y:
          if n.kind == nnkIdent and $n == "pcInline":
            continue
          if n.kind == nnkExprEqExpr:
            var k = n[0]
            if $k == "forr": k = ident("for")
            if $k == "methodd": k = ident("method")
            if n[1].kind == nnkCurly:
              writeLit $k, "=\""
              write n[1][0]
              writeLit "\" "
            else:
              writeLit $k, "=\"", $n[1], "\" "
          elif n.kind == nnkStrLit:
            if $n != $otag:
              writeLit $n, " "
            writeLit $n, " "
        if addSpace:
          writeLit ">\n"
        else:
          writeLit ">"
        if y[^1].kind == nnkStmtList:
          result.add htmlInner(y[^1], indent + 2)
        if addSpace:
          writeLit spaces, "</", tag, ">\n"
        else:
          writeLit "</", tag, ">"

      elif y.len == 2:
        tag.expectKind nnkIdent
        if $tag == "nimcode" and y[1].kind == nnkStmtList: 
          result.add innerNimCode(y[1], indent + 2)
          continue
        # Handle tags without nesting, but with params
        if y[1].kind == nnkExprEqExpr:
          var n = y[1]
          if addSpace:
            writeLit spaces, "<", tag, " "
          else:
            writeLit "<", tag, " "

          if n[1].kind == nnkCurly:
            var k = n[0]
            if $k == "forr": k = ident("for")
            if $k == "methodd": k = ident("method")
            writeLit $k, "=\""
            write n[1][0]
            writeLit "\" "
          else:
            var k = y[1][0]
            if $k == "forr": k = ident("for")
            if $k == "methodd": k = ident("method")
            writeLit $k, "=", $y[1][1]
          if addSpace:
            writeLit ">\n"
          else:
            writeLit ">"
        elif y[1].kind == nnkIdent and $y[1] == "pcInline":
          addSpace = false
        else:
          if addSpace:
            writeLit spaces, "<", tag, ">\n"
          else:
            writeLit "<", tag, ">"

          # Recurse over child          
          result.add htmlInner(y[1], indent + 2)
          writeLit spaces, "</", tag, ">\n"
      else:
        if addSpace:
          writeLit spaces, "<", tag, " "
        else:
          writeLit "<", tag, " "

        for i, n in y:
          if n.kind == nnkExprEqExpr:
            var k = n[0]
            if $k == "forr": k = ident("for")
            if $k == "methodd": k = ident("method")
            writeLit $k, "=\"", $n[1], "\" "
          elif n.kind == nnkStrLit or n.kind == nnkIdent:
            if $n != $otag:
              writeLit $n, " "
        writeLit ">\n"

    else: # Write str lits
      case y.kind:
      of nnkTripleStrLit, nnkStrLit:
        var ys = $y
        ys = ys.strip()
        if startsWith(ys, "pcInline"):
          ys = ys.replace("pcInline ", "")
          result.add quote do:
            result.add `ys`
        else:
          writeLit spaces
          write y
          writeLit "\n"
      else:
        writeLit spaces
        write y
        writeLit "\n"

macro htmlTemplate*(procDef: untyped): untyped =
  procDef.expectKind nnkProcDef

  # Same name as specified
  let name = procDef[0]

  # Return type: string
  var params = @[newIdentNode("string")]
  # Same parameters as specified
  for i in 1..<procDef[3].len:
    params.add procDef[3][i]

  var body = newStmtList()
  body.add newAssignment(newIdentNode("result"),
    newStrLitNode(""))
  # Recurse over DSL definition
  body.add htmlInner(procDef[6])

  # Return a new proc
  result = newStmtList(newProc(name, params, body))
