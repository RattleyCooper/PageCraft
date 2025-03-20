import micros
import macros, strutils

proc escapeHtml*(input: string): string =
  result = newStringOfCap(input.len)
  for c in input:
    case c
    of '&': result.add("&amp;")
    of '<': result.add("&lt;")
    of '>': result.add("&gt;")
    of '"': result.add("&quot;")
    of '\'': result.add("&#39;")
    else: result.add(c)

template write(arg: untyped) =
  result.add newCall("add", newIdentNode("result"), arg)

template writeLit(args: varargs[string, `$`]) =
  write newStrLitNode(args.join)

proc nimcode(nodes: NimNode): NimNode {.compiletime, inline.} =
  quote do:
    `nodes`

proc htmlInner(x: NimNode, indent = 0, stringProc = false, nimCode: bool = false, newLines: bool = true): NimNode {.compiletime.} =
  ## Patch the proc so it runs as PageCraft code.
  #
  
  proc innerNimCode(nn: NimNode, idn = 0, html: bool = false): NimNode {.compiletime, inline.} =    
    ## Recursively patch nim lang constructs so the AST
    ## handles nim code with pagecraft dsl.
    #
    nn.expectKind nnkStmtList
    
    var r = newStmtList()
    for s in nn:
      case s.kind
      of nnkIfStmt, nnkWhenStmt:
        var newIf: NimNode
        if s.kind == nnkIfStmt:
          newIf = nnkIfStmt.newTree()
        else:
          newIf = nnkWhenStmt.newTree()
        for branch in s:
          var ifsStmts = newStmtList()
          case branch.kind
          of nnkElifBranch:
            ifsStmts.add htmlInner(branch[^1], idn)
            var newBranch = nnkElifBranch.newTree()
            newBranch.add branch[0]
            newBranch.add ifsStmts
            newIf.add newBranch
          of nnkElse:
            ifsStmts.add htmlInner(branch[^1], idn)
            var newBranch = nnkElse.newTree()
            newBranch.add ifsStmts
            newIf.add newBranch
          else:
            continue
        r.add quote do:
          `newIf`
      of nnkForStmt:
        var newFor = newStmtList()
        newFor.add htmlInner(s[^1], idn)
        r.add nnkForStmt.newTree(
          s[0], s[1], newFor
        )
      of nnkCall, nnkCommand:
        var newHtmlStmts = newStmtList()
        if s[0].kind == nnkDotExpr:
          newHtmlStmts.add s
        else:
          for stmnt in s:
            newHtmlStmts.add stmnt
        r.add htmlInner(newHtmlStmts, idn, true)
      of nnkCaseStmt:
        var newCase = nnkCaseStmt.newTree()
        var caseIdent = s[0]
        newCase.add caseIdent
        for branch in s[1..^1]:
          var ofStmts = newStmtList()
          case branch.kind
          of nnkOfBranch:
            ofStmts.add htmlInner(branch[^1], idn)
            var newBranch = nnkOfBranch.newTree()
            newBranch.add branch[0]
            newBranch.add ofStmts
            newCase.add newBranch
          of nnkElse:
            ofStmts.add htmlInner(branch[^1], idn)
            var newBranch = nnkElse.newTree()
            newBranch.add ofStmts
            newCase.add newBranch
          else:
            continue

        r.add quote do:
          `newCase`
      of nnkTryStmt:
        var newTry = nnkTryStmt.newTree()
        var tryStmts = htmlInner(s[0], idn)
        newTry.add tryStmts
        for branch in s[1..^1]:
          var excStmts = newStmtList()
          case branch.kind
          of nnkExceptBranch:
            excStmts.add htmlInner(branch[^1], idn)
            var newBranch = nnkExceptBranch.newTree()
            if branch.len > 1:
              for idnt in branch:
                if idnt.kind == nnkIdent:
                  newBranch.add idnt
            newBranch.add excStmts
            newTry.add newBranch
          of nnkFinally:
            excStmts.add htmlInner(branch[^1], idn)
            var newBranch = nnkFinally.newTree()
            newBranch.add excStmts
            newTry.add newBranch
          else:
            continue
        r.add quote do:
          `newTry`      
      of nnkInfix:
        r.add quote do:
          `s`
      of nnkCurly:
        var newHtmlStmts = newStmtList()
        for stmnt in s:
          newHtmlStmts.add stmnt
        r.add htmlInner(newHtmlStmts, idn, true)
      of nnkWhileStmt:
        var newWhile = newStmtList()
        newWhile = htmlInner(s[^1], idn)
        r.add nnkWhileStmt.newTree(
          s[0], newWhile
        )
      of nnkTableConstr:
        var newHtmlStmts = newStmtList()
        for stmnt in s:
          newHtmlStmts.add stmnt
        r.add htmlInner(newHtmlStmts, idn)
      else:
        r.add quote do:
          `s`
    r

  result = newStmtList()
  x.expectKind nnkStmtList
  var spaces = repeat(' ', indent)
  
  for y in x:
    case y.kind
    # try to evaluate things in curly braces
    of nnkCurly: # example: {something.toUpper()} 
      let b = y[0]
      # Calls will evaluate to something else that will
      # automatically add spacing.
      if b.kind != nnkCall: 
        writeLit spaces
      result.add quote do:
        result.add `b`
      if b.kind != nnkCall: 
        writeLit "\n"
    of nnkCommand: # example: html lang="en":
      var tag = y[0]
      if tag.kind == nnkAccQuoted:
        tag = tag[0]
      tag.expectKind nnkIdent

      writeLit spaces, "<", $tag, " "
      var ran = y[1..^1]
      if ran[^1].kind == nnkStmtList:
        ran = y[1..^2]
      for exp in ran:
        if exp.kind == nnkExprEqExpr:
          var k = exp[0]
          var kc = ident(($k).replace("_", "-"))
          if $kc == "typee": kc = ident("type")
          if $kc == "objectt": kc = ident("object")
          if $kc == "forr": kc = ident("for")
          if $kc == "methodd": kc = ident("method")
          if exp[1].kind == nnkCurly:
            writeLit $kc, "=\""
            write exp[1][0]
            writeLit "\" "
          else:
            writeLit $kc, "=\"", $exp[1], "\"", " "
      writeLit ">\n"
      # Command has block of statements, so add closing tag
      if y[^1].kind == nnkStmtList:
        result.add htmlInner(y[^1], indent + 2)
        writeLit spaces, "</", $tag, ">", "\n"
    of nnkCall: # example: div:
      if stringProc:
        writeLit spaces
        result.add quote do:
          result.add `y`.strip()
        writeLit "\n"
        continue

      var tag = y[0]

      if $tag == "nim" or $tag == "nimcode":
        result.add nimcode(y[1])
        continue

      if tag.kind == nnkAccQuoted:
        tag = tag[0]
      tag.expectKind nnkIdent

      writeLit spaces, "<", $tag, ">", "\n"
      if y[1].kind == nnkStmtList:
        result.add htmlInner(y[1], indent + 2)
      else:
        let l = newStmtList()
        l.add y[1]
        result.add htmlInner(l, indent + 2)
        writeLit "\n"
      writeLit spaces, "</", $tag, ">", "\n"
    of nnkIdent: # example: br -> <br>
      var tag = y
      if tag.kind == nnkAccQuoted:
        tag = tag[0]

      writeLit spaces, "<", $tag, ">\n"
    of nnkStrLit, nnkTripleStrLit: # example: "stuff"
      writeLit spaces, ($y).strip(), "\n"
    of nnkPrefix: # example: /html -> </html>
      let pre = y[0]
      var tag = y[1]
      if tag.kind == nnkAccQuoted:
        tag = tag[0]

      case $pre
      of "/":
        writeLit spaces, "</", $tag, ">\n"
      else:
        discard
    # Pass nim language constructs/control flow to
    # enable mixing nim with pagecraft syntax seemlessly
    else: 
      try:
        let ds = newStmtList()
        ds.add y
        result.add innerNimCode(ds, indent)
      except:
        discard

proc baseTemplate(indent: int, procDef: NimNode): NimNode =
  procDef.expectKind nnkProcDef
  
  # Same name as specified
  let name = procDef[0]

  # Return type: string
  var params = @[newIdentNode("string")]
  # Same parameters as specified
  for i in 1..<procDef[3].len:
    params.add procDef[3][i]
  
  var body = newStmtList()
  body.add quote do:
    result = newStringOfCap(1024)
  # body.add newAssignment(newIdentNode("result"),
  #   newStrLitNode(""))
  # Recurse over DSL definition
  body.add htmlInner(procDef[6], indent)

  # Return a new proc
  result = newStmtList(newProc(name, params, body))

macro htmlTemplate*(procDef: untyped): untyped =
  baseTemplate(0, procDef)

macro alignTemplate*(indent: static[int], procDef: untyped): untyped =
  baseTemplate(indent, procDef)
