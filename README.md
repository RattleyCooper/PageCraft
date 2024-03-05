# PageCraft

 Super simple DSL for generating HTML with Nim.  Expands on the concepts introduced at:

 https://hookrace.net/blog/introduction-to-metaprogramming-in-nim/

 to create a more useable DSL for generating HTML in nim. Super helpful for templates for web development You can set arguments on HTML tags, run specific blocks of code in your template (`if/elif`/`case` statements for now), and evaluate code surrounded by `{}`.  This is in early development, so you may run into keywords that do not work, as they are reserved by Nim.  One of these is `div`.  You can write `divv` instead of `div` to create a `<div>` tag.  If you run into anything that doesn't work create an issue or pull request.

 ## Install

 Run `nimble install` inside the directory you extract this repository into or run:

 `nimble install https://github.com/RattleyCooper/PageCraft`

 ## Usage

 Define a `proc`, tag it with `{.htmlTemplate.}`, then you can write HTML tags, add keyword arguments to the tags, and use nim code to help you generate your HTML in the template procedure.  Note that you can use `()` to encapsulate your keyword arguments when creating HTML tags, but it is not required:

 ```nim
import pagecraft

proc myTemplate(title: string, content: string, contentURI: string) {.htmlTemplate.} =
  html lang="en":  # Same as `html(lang="en"):`
    head:
      meta charset="UTF-8"
      meta name="viewport", content="width=device-width, initial-scale=1.0"
      
      # Run an if/elif/else block to modify the title for demo
      if title == "Hello":
        title: {title.toUpper()}
      elif title == "World":
        title: {title.toLower()}
      else: # Else's do not work on if statements yet.
        title: "UNEXPECTED TITLE"
      
      link rel="stylesheet", href="/scripts/prism.css"
    
    body:
      header:
        h1: 
          a href="/", class="homepage-link": {title.toUpper()}
      
      divv class="myContentImage": 
        # Use {} to add variables into to your kwargs.
        # if you don't use {} then nim will treat your
        # kwarg value as a string literal.
        case title:
        of "Hello", "World":
          a href="/":
            img src={contentURI}
        else:
          ""

      # Evaluate stuff using `{}`
      divv class="myContent": {"Here is my content: " & content}
      
      # Add strings to the inner html of a tag
      divv class="contentWrapup":
        """
          I hope you enjoyed my content!
        """


      # If a tag doesn't contain inner html then you need to use
      # call syntax by adding `()`
      divv()

      footer:
        p: "&copy; 2024. All rights reserved. ʕ⊙ᴥ⊙ʔ"
      
      script src="/scripts/prism.js"

echo myTemplate("This is my webpage", "Oh wow, this content!", "/assets/contentImg.png")
 ```

Alternatively you can run `nimcode` blocks to work with data and create variables you can use to fill in the sections of the template. This is the only sure way to run complex nim code with PageCraft.

```nim
import pagecraft

proc makeTag(data: int) {.htmlTemplate.} =
  # Use data to fill in a <p> tag.
  p: 
    $data

proc doStuff() {.htmlTemplate.} =
  nimcode:
    var ptags: string
    for i in 0 .. 10:
      ptags &= makeTag(i)

  html:
    body:
      section:
        divv:
          # not necessary to use {} but helps
          # to distinguish between HTML and 
          # variables.
          {ptags} 


echo doStuff()
```
