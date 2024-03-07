# (ﾉ◕ヮ◕)ﾉ*:･ﾟ✧ PageCraft ✧･ﾟ*:ˋ(◕▽、◕) 

 A powerful DSL for generating dynamic HTML. 
 
 Expands on the concepts introduced at:

 https://hookrace.net/blog/introduction-to-metaprogramming-in-nim/

 to create a more useable DSL for generating HTML in nim. It features full data interpolation, logic/control flow, and error handling through `nimcode`/`pagecraft` blocks.

 ## Install

 Run `nimble install` inside the directory you extract this repository into or run:

 `nimble install https://github.com/RattleyCooper/PageCraft`

 ## Usage

 Define a `proc`, tag it with `{.htmlTemplate.}`, then you can generate HTML using `pagecraft` syntax within that procedure and it will return a string containing the HTML. If you need/want to use nim in your template code use `nimcode`/`pagecraft` blocks as shown in the example code.
 
 This is in early-ish development, so you may run into tags or keywords that do not work, as they are reserved by Nim.  One of these is `div`.  You can write `divv` instead of `div` to create a `<div>` tag. If you run into other tags or keywords that don't work because they're used by nim you can try duplicating the tag's last letter(`type`=>`typee`). 

 Note that running `pagecraft` code within `nimcode` blocks is somewhat limited, but a lot of core language features are available (see list below).

 ### Pagecraft Blocks can evaluate in nested...

 * if/elif/else
 * case
 * for/while 
 * try/else/finally

 ### Pagecraft Blocks can't evaluate in...

 * other nested/blocky things in nim's AST. Basically, if there is a `nnkStmtList` node attached to a `NimNode` in the `nimcode` block and `pagecraft` blocks are located in that `nnkStmtList` they will not be evaluated using PageCraft and you'll get an error during compilation. Support for these language constructs must be added manually until a different solution can be implemented.

## Examples

 ```nim
import pagecraft

# Alternatively pass in records from a debby query,
# or params you can use for a db query.
proc myTemplate(title: string, content: string, contentURI: string, css: string) {.htmlTemplate.} =
  # Run some nim code and set a new variable.
  nimcode:
    echo "This is regular nim code"
    var newVar = "This is a newly created variable"

  # Add raw strings
  "<!DOCTYPE html>"
  # Define HTML using whitespace instead of <>
  html lang="en":  # Same as `html(lang="en"):`
    head:
      meta charset="UTF-8"
      meta name="viewport", content="width=device-width, initial-scale=1.0"
      
      # Mix pagecraft code back into nim.
      nimcode:
        if title == "Hello":
          pagecraft: 
            title: 
              # Evaluate strings using `{}`
              {title.toUpper()}
        elif title == "World":
          pagecraft:
            title: {title.toLower()}
        else:
          pagecraft:
            title: "UNEXPECTED TITLE"
      
      # Use `{}` when inserting into tag keywords
      link rel="stylesheet", href={css}
    
    body:
      header:
        h1: 
          a href="/", class="homepage-link": 
            {title.toUpper()}

        # Let's use the new variable we created.
        p: {newVar}
      
      divv class="myContentImage": 
        # If you don't use {} in tag kwargs then 
        # nim will treat your kwarg value as a 
        # string literal.
        nimcode:
          case title:
          of "Hello", "World":
            pagecraft:
              a href="/":
                img src={contentURI}
          else:
            ""
      
      # Running more pagecraft from nimcode blocks. 
      divv class="moreContent":
        nimcode:
          for x in 0 .. 10:
            pagecraft:
              p: "Remix pagecraft code into nim " & {$x}

      # Access the currently generated HTML through
      # the `result` variable in nimcode blocks.
      nimcode:
        echo "this is the current HTML:\n" & result

      divv class="myContent": 
        {"Here is my content: " & content}
      
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

echo myTemplate("This is my webpage", "Oh wow, this content!", "/assets/contentImg.png", "/scripts/prism.css")
 ```

## PageCraft, Debby and Mummy

Pull in data with `Debby`, generate HTML with `PageCraft` and serve it with `Mummy`.

```nim
import mummy, mummy/routers
import debby/[pools, sqlite]
import src/pagecraft

# Use debby pools with mummy to be safe
let pool = newPool()
for i in 0 ..< 10:
  pool.add openDatabase("site.db")

# DB Model
type Auto = ref object
  id: int
  make: string
  model: string
  year: int

# Migrate
pool.dropTableIfExists(Auto)
pool.createTable(Auto)
var theAuto1 = Auto(
  make: "Chevrolet",
  model: "Camaro Z28",
  year: 1970
)
var theAuto2 = Auto(
  make: "Dodge",
  model: "Challenger",
  year: 1970
)
pool.insert(theAuto1)
pool.insert(theAuto2)

# Tiny stylesheet for sanity
const style = """body { font-family: Arial, sans-serif; margin: 0; padding: 0; background-color: #f4f4f4; }
section { padding: 20px; }
div { margin-bottom: 10px; padding: 10px; background-color: #ffffff; border: 1px solid #dddddd; border-radius: 4px; }"""

proc carCard(car: Auto) {.htmlTemplate.} =
  section class="auto-section":
    divv class="auto-div":
      p: {"Make: " & car.make}
      p: {"Model: " & car.model}
      p: {"Year: " & $car.year}

proc carsSection(cars: seq[Auto]) {.htmlTemplate.} =
  # Main Autos section
  section:
    h2: 
      "Check out my cars!"
    divv:
      # ~~~ Insert a new car card for each new car
      nimcode:
        for car in cars:
          pagecraft:
            {carCard(car)}

# Generate our dynamic HTML
proc indexTemplate(pool: Pool) {.htmlTemplate.} =
  nimcode:  
    var cars = pool.filter(Auto, it.year == 1970)

  # Define our site.
  "<!DOCTYPE html>"
  html lang="en":
    head:
      title: "Some Site"
      style: {style} # Style for sanity
      
    body:
      h1: "Welcome to my car website!"
      # Only display cars section if we have
      # cars to show.
      nimcode:
        if cars.len > 0:
          pagecraft:
            {carsSection(cars)}
        else:
          pagecraft:
            p: "No cars :("

proc indexHandler(request: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/html"

  request.respond(200, headers, indexTemplate(pool))

var router: Router
router.get("/", indexHandler)

let server = newServer(router)
echo "Serving on http://localhost:8080"
server.serve(Port(8080))
```
