# ✧ PageCraft ✧

 A powerful Template Engine/DSL for generating dynamic HTML. 
 
 Expands on the concepts introduced at:

 https://hookrace.net/blog/introduction-to-metaprogramming-in-nim/

 to create a more feature rich DSL for generating HTML in nim. It features full data interpolation, logic/control flow, and exception handling.

 ## Install

 Run `nimble install` inside the directory you extract this repository into or run:

 `nimble install https://github.com/RattleyCooper/PageCraft`

 ## Usage

 Define a `proc`, tag it with `{.htmlTemplate.}`, then you can generate HTML using `pagecraft` syntax within that procedure and it will return a string containing the HTML. If you need/want to use nim in your template code you can mix in most nim control flow constructs seamlessly, but if you want to run nim code without the macro messing with anything you can put the code into a `nim` or `nimcode` block. This will bypass pagecraft's evaluation of the code entirely.
 
 This is in early-ish development, so you may run into tags or keywords that do not work, as they are reserved by Nim. One of these is `div`. You can write `divv` instead of `div` to create a `<div>` tag. If you run into other tags or keywords that don't work because they're used by nim you can try duplicating the tag's last letter(`type`=>`typee`). They same goes for keywords in HTML tags.


## Examples

 ```nim
import pagecraft
import strutils

# Alternatively pass in records from a debby query,
# or params you can use for a db query.
proc myTemplate(title: string, content: string, contentURI: string, css: string) {.htmlTemplate.} =
  # Run some nim code and set a new variable.
  nimcode:
    echo "This is regular nim code"
    var newVar = "This is a newly created variable"

  # Add raw strings
  "<!DOCTYPE html>"

  # Access the currently generated HTML through
  # the `result` variable.
  nimcode:
    echo "this is the current HTML:\n" & result

  # Define HTML using whitespace instead of <>
  html lang="en":
    head:
      meta charset="UTF-8"
      meta name="viewport", content="width=device-width, initial-scale=1.0"
      
      # Mix pagecraft with nim
      if title == "Hello":
        title: 
          # Evaluate strings using `{}`
          {title.toUpper()}
      elif title == "World":
        title: {title.toLower()}
      else:
        title: "UNEXPECTED TITLE"
      
      # Use `{}` when inserting into tag keywords
      link rel="stylesheet", href={css} # adds "" automatically
    
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
        case title:
        of "Hello", "World":
          pagecraft:
            a href="/":
              img src={contentURI}
        else:
          ""
      
      # Running more pagecraft with nim. 
      divv class="moreContent":
        for x in 0 .. 10:
          p: {"Remix pagecraft code into nim " & $x}

      divv class="myContent": 
        h2: "Here is my content!"
        p: {content}
      
      # Add strings to the inner html of a tag
      divv class="contentWrapup":
        """
          I hope you enjoyed my content!
        """

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
import pagecraft
import strutils

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

# Align the template stubs using `alignTemplate`
proc carCard(car: Auto) {.alignTemplate: 8.} =
  divv class="auto-div", id={$car.id}:
    p: {"Make: " & car.make}
    p: {"Model: " & car.model}
    p: {"Year: " & $car.year}

proc carsSection(cars: seq[Auto]) {.alignTemplate: 2.} =
  # Main Autos section
  section:
    h2: 
      "Check out my cars!"
    divv:
      # ~~~ Insert a new car card for each new car
      section class="auto-section":
        for car in cars:
          {carCard(car)}

# Generate our dynamic HTML
proc indexTemplate(cars: seq[Auto]) {.htmlTemplate.} =
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
      if cars.len > 0:
        {carsSection(cars)}
      else:
        p: "No cars :("

proc indexHandler(request: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/html"

  var cars = pool.filter(Auto, it.year == 1970)
  request.respond(200, headers, indexTemplate(cars))

var router: Router
router.get("/", indexHandler)

let server = newServer(router)
echo "Serving on http://localhost:8080"
server.serve(Port(8080))
```
