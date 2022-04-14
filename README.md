# kong-oathkeeper-plugin
This Kong API Gateway Plugin can be used to authenticate and authorize requests through the ORY OathKeeper in decision API mode.

## Installation
1. Create directory called `/usr/local/share/lua/5.1/kong/plugins/oathkeeper` on Kong node and copy contents of `/oathkeeper` directory there.
2. Update your `KONG_PLUGINS` environment variable or configuration to include `oathkeeper` (e.g. `KONG_PLUGINS=bundled,oathkeeper`).
3. Restart Kong and you're ready to go.

## Configuration
You can add the plugin on top of an API by executing the following request on your Kong server:

#### Through API request
```shell
$ curl -X POST http://kong:8001/apis/{api}/plugins \
    --data "name=oathkeeper" \
    --data "config.url=http://oathkeeper:4456/decisions" \
    --data "config.timeout=200" \
    --data "config.forward_headers[1]=Authorization" \
    --data "config.return_headers[1]=X-User-Id"
```

#### Declarative way
```yaml
services:
- name: ms-auth
  url: http://ms-auth:8000
  tags:
    - ms-auth
  routes:
    - name: ms-auth
      paths:
        - /ms-auth
      strip_path: true
  plugins:
    - name: oathkeeper
      config:
        url: http://oathkeeper:4456/decisions
        timeout: 200 # milliseconds
        forward_headers: ["Authorization"]
        return_headers: ["X-User-Id"]
```

#### Parameters
| form parameter         | required | default | description                                                                                                                                                        |
| ---------------------- | -------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| name                   | yes      |         | The name of the plugin to use, in this case: oathkeeper                                                                                                            |
| config.url             | yes      |         | The URL to decision API of the ORY OathKeeper where the plugin will make a request before proxying the original request. (e.g. `http://oathkeeper:4456/decisions`) |
| config.timeout         | no       | 60000   | Timeout (miliseconds) for the request to the URL specified above.                                                                                                  |
| config.forward_headers | no       |         | The array of headers' name from original request which will be passed to ORY OathKeeper decision API. (e.g. `["Authorization"]`)                                   |
| config.return_headers  | no       |         | The array of headers' name from ORY OathKeeper response which will be passed to proxying request. (e.g. `["X-User-Id"]`)                                           |

## Author
Timofey Solovyev