return {
  no_consumer = true,
  fields = {
    url = {required = true, type = "string"},
    timeout = { default = 10000, type = "number" },
    debug = {default = false, type = "boolean" },
    forward_headers = { type = "array" },
    return_headers = { type = "array" }
  }
}