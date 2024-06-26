# vim:set ft= ts=4 sw=4 et fdm=marker:

our $SkipReason;

BEGIN {
    if ($ENV{TEST_NGINX_EVENT_TYPE}
        && $ENV{TEST_NGINX_EVENT_TYPE} !~ /^kqueue|epoll|eventport$/)
    {
        $SkipReason = "unavailable for the event type '$ENV{TEST_NGINX_EVENT_TYPE}'";
    }
}

use Test::Nginx::Socket::Lua $SkipReason ? (skip_all => $SkipReason) : ();

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 2);

our $HtmlDir = html_dir;

our $HttpConfig = qq{
    lua_package_path "$::HtmlDir/?.lua;./?.lua;;";
    lua_worker_thread_vm_pool_size 1;
};

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: hello from worker thread
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", hello_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return "hello"
end
return {hello=hello}
--- request
GET /hello
--- response_body
true : hello



=== TEST 2: thread_pool not found
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", hello_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return "hello"
end
return {hello=hello}
--- request
GET /hello
--- response_body
false : thread pool testpool not found



=== TEST 3: pass table
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, ok_or_err = ngx.run_worker_thread("testpool", "hello", "hello", {["hello"]="world", [1]={["embed"]=1}})
        ngx.say(ok, " , ", ok_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello(arg1)
    if arg1.hello == "world" and arg1[1].embed == 1 then
        return true
    end
    return false
end
return {hello=hello}
--- request
GET /hello
--- response_body
true , true



=== TEST 4: expecting at least 3 arguments
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, err = ngx.run_worker_thread("testpool")
        ngx.say(ok, " : ", err)
    }
}
--- request
GET /hello
--- response_body
false : expecting at least 3 arguments



=== TEST 5: base64
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, base64 = ngx.run_worker_thread("testpool", "hello", "enc", "hello")
        ngx.say(ok, " , ", base64 == "aGVsbG8=")
    }
}
--- user_files
>>> hello.lua
local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

local function enc(data)
    return ((data:gsub('.', function(x)
        local r,b='',x:byte()
        for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
        return r;
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end

return {enc=enc}
--- request
GET /hello
--- response_body
true , true



=== TEST 6: return table
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, ret = ngx.run_worker_thread("testpool", "hello", "hello")
        if ret.hello == "world" and ret[1].embed == 1 then
            ngx.say(ok, " , ", true)
        end
    }
}
--- user_files
>>> hello.lua
local function hello()
    return {["hello"]="world", [1]={["embed"]=1}}
end
return {hello=hello}
--- request
GET /hello
--- response_body
true , true



=== TEST 7: unsupported argument type
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local function dummy() end
        local ok, err = ngx.run_worker_thread("testpool", "hello", "hello", dummy)
        ngx.say(ok, " : ", err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return "hello"
end
return {hello=hello}
--- request
GET /hello
--- response_body
false : unsupported Lua type: LUA_TFUNCTION in the argument



=== TEST 8: multiple return values
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, res1, res2 = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", res1, " , ", res2)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return "hello", 200
end
return {hello=hello}
--- request
GET /hello
--- response_body
true : hello , 200



=== TEST 9: module not found
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", err)
    }
}
--- request
GET /hello
--- response_body_like
false : module 'hello' not found.*



=== TEST 10: the number of Lua VM exceeds the pool size
--- no_http2
--- quic_max_idle_timeout: 5
--- main_config
    thread_pool testpool threads=100;
--- http_config eval: $::HttpConfig
--- config
location /foo {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", hello_or_err)
    }
}

location /bar {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, foobar_or_err = ngx.run_worker_thread("testpool", "foobar", "foobar")
        ngx.say(ok, " : ", foobar_or_err)
    }
}

location /t {
    set $port $TEST_NGINX_SERVER_PORT;

    content_by_lua_block {
        local function t(path)
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local req = "GET " .. path .. " HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            local ret, err, part = sock:receive("*a")
            local _, idx = string.find(ret, "\r\n\r\n");
            idx = idx + 1
            ngx.print(string.sub(ret, idx))
            ok, err = sock:close()
        end

        local t1 = ngx.thread.spawn(t, "/foo")
        local t2 = ngx.thread.spawn(t, "/bar")
        ngx.thread.wait(t1)
        ngx.thread.wait(t2)
    }
}
--- user_files
>>> hello.lua
local function hello()
    os.execute("sleep 3")
    return "hello"
end
return {hello=hello}
>>> foobar.lua
local function foobar()
    return "foobar"
end
return {foobar=foobar}
--- request
GET /t
--- response_body eval
"false : no available Lua vm\ntrue : hello\n"
--- timeout: 10



=== TEST 11: kill uthread before worker thread callback
--- no_http2
--- quic_max_idle_timeout: 10
--- main_config
    thread_pool testpool threads=100;
--- http_config eval: $::HttpConfig
--- config
location /foo {
    default_type 'text/plain';

    content_by_lua_block {
        local function t()
            local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
            ngx.say(ok, " : ", hello_or_err)
        end
        local t1 = ngx.thread.spawn(t)
        if ngx.var.arg_kill == "kill" then
            ngx.thread.kill(t1)
            ngx.say("killed")
        end
    }
}

location /t {
    set $port $TEST_NGINX_SERVER_PORT;

    content_by_lua_block {
        local function t(path)
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local req = "GET " .. path .. " HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            local ret, err, part = sock:receive("*a")
            local _, idx = string.find(ret, "\r\n\r\n");
            idx = idx + 1
            ngx.print(string.sub(ret, idx))
            ok, err = sock:close()
        end

        local t1 = ngx.thread.spawn(t, "/foo?kill=kill")
        ngx.thread.wait(t1)
        ngx.sleep(4)
        local t2 = ngx.thread.spawn(t, "/foo")
        ngx.thread.wait(t2)
    }
}
--- user_files
>>> hello.lua
local function hello()
    os.execute("sleep 1")
    return "hello"
end
return {hello=hello}
>>> foobar.lua
local function foobar()
    return "foobar"
end
return {foobar=foobar}
--- request
GET /t
--- response_body eval
"killed\ntrue : hello\n"
--- timeout: 10



=== TEST 12: exit before worker thread callback
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local function t()
            local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
            ngx.say(ok, " : ", hello_or_err)
        end
        ngx.thread.spawn(t)
        ngx.exit(200)
    }
}
--- user_files
>>> hello.lua
local function hello()
    os.execute("sleep 3")
    return "hello"
end
return {hello=hello}
--- request
GET /hello
--- response_body
--- timeout: 10



=== TEST 13: unsupported argument type in nested table
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local function dummy() end
        local ok, err = ngx.run_worker_thread("testpool", "hello", "hello",
                    {["hello"]="world", [1]={["embed"]=1, ["dummy"]=dummy}})
        ngx.say(ok, " : ", err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return "hello"
end
return {hello=hello}
--- request
GET /hello
--- response_body
false : unsupported Lua type: LUA_TFUNCTION in the argument



=== TEST 14: return table with unsupported type
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, ret = ngx.run_worker_thread("testpool", "hello", "hello")
        if ok == false then
            ngx.say("false", " , ", ret)
        end
        if ret.hello == "world" and ret[1].embed == 1 then
            ngx.say(ok, " , ", true)
        end
    }
}
--- user_files
>>> hello.lua
local function hello()
    local function dummy() end
    return {["hello"]="world", [1]={["embed"]=1, ["dummy"]=dummy}}
end
return {hello=hello}
--- request
GET /hello
--- response_body
false , unsupported Lua type: LUA_TFUNCTION in the return value



=== TEST 15: the type of module name is not string
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local function dummy() end
        local ok, err = ngx.run_worker_thread("testpool", dummy, "hello")
        ngx.say(ok, " : ", err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return "hello"
end
return {hello=hello}
--- request
GET /hello
--- response_body
false : module name should be a string



=== TEST 16: the type of function name is not string
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local function dummy() end
        local ok, err = ngx.run_worker_thread("testpool", "hello", dummy)
        ngx.say(ok, " : ", err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return "hello"
end
return {hello=hello}
--- request
GET /hello
--- response_body
false : function name should be a string



=== TEST 17: the type of thread pool name is not string
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local function dummy() end
        local ok, err = ngx.run_worker_thread(dummy, "hello", "hello")
        ngx.say(ok, " : ", err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return "hello"
end
return {hello=hello}
--- request
GET /hello
--- response_body
false : threadpool should be a string



=== TEST 18: ngx.encode_base64
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", hello_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return ngx.encode_base64("hello")
end
return {hello=hello}
--- request
GET /hello
--- response_body
true : aGVsbG8=



=== TEST 19: ngx.config.subsystem
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", hello_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return ngx.config.subsystem
end
return {hello=hello}
--- request
GET /hello
--- response_body
true : http



=== TEST 20: ngx.hmac_sha1
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", hello_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello()
  local key = "thisisverysecretstuff"
  local src = "some string we want to sign"
  local digest = ngx.hmac_sha1(key, src)
  return ngx.encode_base64(digest)
end
return {hello=hello}
--- request
GET /hello
--- response_body
true : R/pvxzHC4NLtj7S+kXFg/NePTmk=



=== TEST 21: ngx.encode_args
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", hello_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello()
  return ngx.encode_args({foo = 3, ["b r"] = "hello world"})
end
return {hello=hello}
--- request
GET /hello
--- response_body eval
qr/foo=3&b%20r=hello%20world|b%20r=hello%20world&foo=3/



=== TEST 22: ngx.decode_args
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, ret = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", ret.a, " : ", ret.b)
    }
}
--- user_files
>>> hello.lua
local function hello()
  local args = "a=bar&b=foo"
  args = ngx.decode_args(args)
  return args
end
return {hello=hello}
--- request
GET /hello
--- response_body
true : bar : foo



=== TEST 23: ngx.quote_sql_str
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    location /hello {
        content_by_lua '
          local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello", "a\\026b\\026")
          ngx.say(ok, " : ", hello_or_err)
        ';
    }
--- user_files
>>> hello.lua
local function hello(str)
  return ngx.quote_sql_str(str)
end
return {hello=hello}
--- request
GET /hello
--- response_body
true : 'a\Zb\Z'



=== TEST 24: ngx.decode_base64
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", hello_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return ngx.decode_base64("aGVsbG8=")
end
return {hello=hello}
--- request
GET /hello
--- response_body
true : hello



=== TEST 25: ngx.crc32_short
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", hello_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return ngx.crc32_short("hello, world")
end
return {hello=hello}
--- request
GET /hello
--- response_body
true : 4289425978



=== TEST 26: ngx.crc32_long
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", hello_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return ngx.crc32_long("hello, world")
end
return {hello=hello}
--- request
GET /hello
--- response_body
true : 4289425978



=== TEST 27: ngx.md5_bin
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", hello_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    local s = ngx.md5_bin(45)
    s = string.gsub(s, ".", function (c)
            return string.format("%02x", string.byte(c))
        end)
    return s
end
return {hello=hello}
--- request
GET /hello
--- response_body
true : 6c8349cc7260ae62e3b1396831a8398f



=== TEST 28: ngx.md5
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", hello_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return ngx.md5("hello")
end
return {hello=hello}
--- request
GET /hello
--- response_body
true : 5d41402abc4b2a76b9719d911017c592



=== TEST 29: ngx.config.debug
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", hello_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return ngx.config.debug
end
return {hello=hello}
--- request
GET /hello
--- response_body_like chop
^true : (?:true|false)$



=== TEST 30: ngx.config.prefix
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", hello_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return ngx.config.prefix()
end
return {hello=hello}
--- request
GET /hello
--- response_body_like chop
^true : \/\S+$



=== TEST 31: ngx.config.nginx_version
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", hello_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return ngx.config.nginx_version
end
return {hello=hello}
--- request
GET /hello
--- response_body_like chop
^true : \d+$



=== TEST 32: ngx.config.nginx_configure
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(hello_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return ngx.config.nginx_configure()
end
return {hello=hello}
--- request
GET /hello
--- response_body_like chop
^\s*\-\-[^-]+



=== TEST 33: ngx.config.ngx_lua_version
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", hello_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return ngx.config.ngx_lua_version
end
return {hello=hello}
--- request
GET /hello
--- response_body_like chop
^true : \d+$



=== TEST 34: write_log_file
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /write_log_file {
    default_type 'text/plain';

    access_by_lua_block {
        local ok, err = ngx.run_worker_thread("testpool", "write_log_file", "log", ngx.var.arg_str)
        if not ok then
            ngx.say(ok, " : ", err)
            return
        end
        ngx.say(ok)
    }
}
--- user_files
>>> write_log_file.lua
local function log(str)
    local file, err = io.open("/tmp/tmp.log", "w")
    if not file then
        return false, err
    end
    file:write(str)
    file:flush()
    file:close()
    return true
end
return {log=log}
--- request
GET /write_log_file?str=hello
--- response_body
true



=== TEST 35: shdict get, int value
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
"
    lua_shared_dict dogs 10m;
    lua_package_path '$::HtmlDir/?.lua;./?.lua;;';
"
--- config
location /dictget {
    default_type 'text/plain';

    access_by_lua_block {
        local dogs = ngx.shared.dogs
        dogs:set("Jim", 8)
        local ok, err = ngx.run_worker_thread("testpool", "test_shdict", "dictget")
        ngx.say(ok, ",", err)
    }
}
--- user_files
>>> test_shdict.lua
local function dictget(str)
    local dogs = ngx.shared.dogs
    return dogs:get("Jim")
end
return {dictget=dictget}
--- request
GET /dictget
--- response_body
true,8



=== TEST 36: shdict set nil in main thread
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
"
    lua_shared_dict dogs 10m;
    lua_package_path '$::HtmlDir/?.lua;./?.lua;;';
"
--- config
location /dictget {
    default_type 'text/plain';

    access_by_lua_block {
        local dogs = ngx.shared.dogs
        dogs:set("Jim", 8)
        local ok, err = ngx.run_worker_thread("testpool", "test_shdict", "dictget")
        ngx.say(ok, ",", err)
        dogs:set("Jim", nil)
        local ok, err = ngx.run_worker_thread("testpool", "test_shdict", "dictget")
        ngx.say(ok, ",", err)
    }
}
--- user_files
>>> test_shdict.lua
local function dictget(str)
    local dogs = ngx.shared.dogs
    return dogs:get("Jim")
end
return {dictget=dictget}
--- request
GET /dictget
--- response_body
true,8
true,nil



=== TEST 37: shdict set nil in worker thread
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
"
    lua_shared_dict dogs 10m;
    lua_package_path '$::HtmlDir/?.lua;./?.lua;;';
"
--- config
location /dictsetnil {
    default_type 'text/plain';

    access_by_lua_block {
        local dogs = ngx.shared.dogs
        dogs:set("Jim", 8)
        local ok, err = ngx.run_worker_thread("testpool", "test_shdict", "dictsetnil")
        ngx.say(ok, ",", err)
        ngx.say(ok, ",", dogs:get("Jim"))
    }
}
--- user_files
>>> test_shdict.lua
local function dictsetnil(str)
    local dogs = ngx.shared.dogs
    return dogs:set("Jim", nil)
end
return {dictsetnil=dictsetnil}
--- request
GET /dictsetnil
--- response_body
true,true
true,nil



=== TEST 38: shdict get_stale
For http3: curl: (55) ngtcp2_conn_handle_expiry returned error: ERR_IDLE_CLOSE
--- skip_eval: 2:$ENV{TEST_NGINX_USE_HTTP3}
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
"
    lua_shared_dict dogs 10m;
    lua_package_path '$::HtmlDir/?.lua;./?.lua;;';
"
--- config
location /dictget {
    default_type 'text/plain';

    access_by_lua_block {
        local dogs = ngx.shared.dogs
        dogs:set("Jim", 8, 1)
        ngx.sleep(2)
        local ok, err = ngx.run_worker_thread("testpool", "test_shdict", "dictget")
        ngx.say(ok, ",", err)
    }
}
--- user_files
>>> test_shdict.lua
local function dictget(str)
    local dogs = ngx.shared.dogs
    return dogs:get_stale("Jim")
end
return {dictget=dictget}
--- request
GET /dictget
--- response_body
true,8



=== TEST 39: shdict add failed
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
"
    lua_shared_dict dogs 10m;
    lua_package_path '$::HtmlDir/?.lua;./?.lua;;';
"
--- config
location /dictadd {
    default_type 'text/plain';

    access_by_lua_block {
        local dogs = ngx.shared.dogs
        dogs:set("Jim", 8)
        local ok, err, err2 = ngx.run_worker_thread("testpool", "test_shdict", "dictadd")
        ngx.say(ok, ",", err, ",", err2)
    }
}
--- user_files
>>> test_shdict.lua
local function dictadd(str)
    local dogs = ngx.shared.dogs
    local success, err = dogs:add("Jim", "hello")
    return success, err
end
return {dictadd=dictadd}
--- request
GET /dictadd
--- response_body
true,false,exists



=== TEST 40: shdict force add
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
"
    lua_shared_dict dogs 6m;
    lua_package_path '$::HtmlDir/?.lua;./?.lua;;';
"
--- config
location /dictadd {
    default_type 'text/plain';

    access_by_lua_block {
        local dogs = ngx.shared.dogs
        local bigstr = string.rep("A", 1024*1024*3)
        dogs:set("Jim", bigstr)
        local ok, ret, err, forcible = ngx.run_worker_thread("testpool", "test_shdict", "dictadd")
        ngx.say(ok, ",", ret, ",", forcible, ",", dogs:get("Jim"))
    }
}
--- user_files
>>> test_shdict.lua
local function dictadd(str)
    local dogs = ngx.shared.dogs
    local bigstr = string.rep("A", 1024*1024*5)
    local success, err, forcible = dogs:add("King", bigstr)
    return success, err, forcible
end
return {dictadd=dictadd}
--- request
GET /dictadd
--- response_body
true,true,true,nil



=== TEST 41: shdict replace
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
"
    lua_shared_dict dogs 6m;
    lua_package_path '$::HtmlDir/?.lua;./?.lua;;';
"
--- config
location /dictreplace {
    default_type 'text/plain';

    access_by_lua_block {
        local dogs = ngx.shared.dogs
        local bigstr = string.rep("A", 1024*1024*3)
        dogs:set("Jim", bigstr)
        local ok, ret, err = ngx.run_worker_thread("testpool", "test_shdict", "dictreplace")
        ngx.say(ok, ",", ret, ",", err, ",", dogs:get("Jim"))
    }
}
--- user_files
>>> test_shdict.lua
local function dictreplace(str)
    local dogs = ngx.shared.dogs
    local success, err = dogs:replace("Jim", 8)
    return success, err
end
return {dictreplace=dictreplace}
--- request
GET /dictreplace
--- response_body
true,true,nil,8



=== TEST 42: shdict replace not found
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
"
    lua_shared_dict dogs 6m;
    lua_package_path '$::HtmlDir/?.lua;./?.lua;;';
"
--- config
location /dictreplace {
    default_type 'text/plain';

    access_by_lua_block {
        local dogs = ngx.shared.dogs
        local ok, ret, err = ngx.run_worker_thread("testpool", "test_shdict", "dictreplace")
        ngx.say(ok, ",", ret, ",", err)
    }
}
--- user_files
>>> test_shdict.lua
local function dictreplace(str)
    local dogs = ngx.shared.dogs
    local success, err = dogs:replace("Jim", 8)
    return success, err
end
return {dictreplace=dictreplace}
--- request
GET /dictreplace
--- response_body
true,false,not found



=== TEST 43: shdict incr
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
"
    lua_shared_dict dogs 6m;
    lua_package_path '$::HtmlDir/?.lua;./?.lua;;';
"
--- config
location /dictincr {
    default_type 'text/plain';

    access_by_lua_block {
        local dogs = ngx.shared.dogs
        local success, err = dogs:set("Jim", 8)
        local ok, ret, err = ngx.run_worker_thread("testpool", "test_shdict", "dictincr")
        ngx.say(ok, ",", ret, ",", err, ",", dogs:get("Jim"))
    }
}
--- user_files
>>> test_shdict.lua
local function dictincr(str)
    local dogs = ngx.shared.dogs
    local success, err = dogs:incr("Jim", 1)
    return success, err
end
return {dictincr=dictincr}
--- request
GET /dictincr
--- response_body
true,9,nil,9



=== TEST 44: shdict lpush lpop
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
"
    lua_shared_dict dogs 6m;
    lua_package_path '$::HtmlDir/?.lua;./?.lua;;';
"
--- config
location /dictlpush {
    default_type 'text/plain';

    access_by_lua_block {
        local dogs = ngx.shared.dogs
        dogs:lpush("Jim", 8)
        dogs:lpush("Jim", 9)
        local ok, val, len, err = ngx.run_worker_thread("testpool", "test_shdict", "dictlpush")
        ngx.say(ok, ",", val, ",", len, ",", err, ",", dogs:lpop("Jim"))
    }
}
--- user_files
>>> test_shdict.lua
local function dictlpush(str)
    local dogs = ngx.shared.dogs
    local val = dogs:lpop("Jim")
    local len, err = dogs:lpush("Jim", 7)
    return val, len, err
end
return {dictlpush=dictlpush}
--- request
GET /dictlpush
--- response_body
true,9,2,nil,7



=== TEST 45: shdict expire ttl
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
"
    lua_shared_dict dogs 6m;
    lua_package_path '$::HtmlDir/?.lua;./?.lua;;';
"
--- config
location /dictexpire {
    default_type 'text/plain';

    access_by_lua_block {
        local dogs = ngx.shared.dogs
        dogs:set("Jim", 8)
        local ok, success, err = ngx.run_worker_thread("testpool", "test_shdict", "dictexpire")
        ngx.say(ok, ",", success, ",", err, ",", dogs:ttl("Jim") <= 1)
    }
}
--- user_files
>>> test_shdict.lua
local function dictexpire(str)
    local dogs = ngx.shared.dogs
    local success, err = dogs:expire("Jim", 1)
    return success, err
end
return {dictexpire=dictexpire}
--- request
GET /dictexpire
--- response_body
true,true,nil,true



=== TEST 46: shdict flush_all
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
"
    lua_shared_dict dogs 6m;
    lua_package_path '$::HtmlDir/?.lua;./?.lua;;';
"
--- config
location /dictexpire {
    default_type 'text/plain';

    access_by_lua_block {
        local dogs = ngx.shared.dogs
        dogs:set("Jim", 8)
        dogs:set("King", 9)
        local ok = ngx.run_worker_thread("testpool", "test_shdict", "dictexpire")
        ngx.say(ok, ",", dogs:get("Jim"), ",", dogs:get("King"))
    }
}
--- user_files
>>> test_shdict.lua
local function dictexpire(str)
    local dogs = ngx.shared.dogs
    dogs:flush_all()
end
return {dictexpire=dictexpire}
--- request
GET /dictexpire
--- response_body
true,nil,nil



=== TEST 47: shdict get_keys
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
"
    lua_shared_dict dogs 6m;
    lua_package_path '$::HtmlDir/?.lua;./?.lua;;';
"
--- config
location /dictgetkeys {
    default_type 'text/plain';

    access_by_lua_block {
        local dogs = ngx.shared.dogs
        dogs:set("Jim", 8)
        dogs:set("King", 9)
        local ok, keys = ngx.run_worker_thread("testpool", "test_shdict", "dictgetkeys")
        ngx.say(ok, ",", table.concat(keys, ":"))
    }
}
--- user_files
>>> test_shdict.lua
local function dictgetkeys(str)
    local dogs = ngx.shared.dogs
    return dogs:get_keys()
end
return {dictgetkeys=dictgetkeys}
--- request
GET /dictgetkeys
--- response_body
true,Jim:King



=== TEST 48: unsupported argument type in self-reference table
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local t = {}
        t.a = t
        local ok, ok_or_err = ngx.run_worker_thread("testpool", "hello", "hello", t)
        ngx.say(ok, " , ", ok_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello(arg1)
    return true
end
return {hello=hello}
--- request
GET /hello
--- response_body
false , suspicious circular references, table depth exceed max depth: 100 in the argument



=== TEST 49: unsupported argument type in circular-reference table
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local t = {}
        local s = {}
        t.a = s
        s.b = t

        local ok, ok_or_err = ngx.run_worker_thread("testpool", "hello", "hello", t)
        ngx.say(ok, " , ", ok_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello(arg1)
    return true
end
return {hello=hello}
--- request
GET /hello
--- response_body
false , suspicious circular references, table depth exceed max depth: 100 in the argument



=== TEST 50: call run_worker_thread twice
--- main_config
    thread_pool testpool threads=1;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", hello_or_err)

        ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", hello_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return "hello"
end
return {hello=hello}
--- request
GET /hello
--- response_body
true : hello
true : hello



=== TEST 51: big object
--- main_config
    thread_pool testpool threads=1;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", #hello_or_err)

        local ok, gcsize_or_err = ngx.run_worker_thread("testpool", "hello", "gcsize")
        ngx.say(ok, " : ", gcsize_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return string.rep("helloworld", 1000000)
end

local function gcsize()
    return collectgarbage("count")
end

return {
    hello = hello,
    gcsize = gcsize
}
--- request
GET /hello
--- response_body eval
qr/\Atrue : 10000000
true : \d{3,4}\.\d+
\z/ms
