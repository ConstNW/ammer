package ammer.stub;

import ammer.Config.AmmerLibraryConfig;

using ammer.FFITools;
using StringTools;

class StubLua {
  static var library:AmmerLibraryConfig;
  static var lb:LineBuf;

  static function generateHeader():Void {
    lb.ai("#ifdef __cplusplus\n");
    lb.ai("extern \"C\" {\n");
    lb.ai("#endif\n");
    lb.ai('#include <lua.h>\n');
    lb.ai('#include <lualib.h>\n');
    lb.ai('#include <lauxlib.h>\n');
    lb.ai("#ifdef __cplusplus\n");
    lb.ai("}\n");
    lb.ai("#endif\n");
    for (header in library.headers)
      lb.ai('#include <${header}>\n');
  }

  static function mapTypeC(t:FFIType, name:String):String {
    return (switch (t) {
      case SizeOfReturn: "size_t" + (name != "" ? ' $name' : "");
      case _: StubBaseC.mapTypeC(t, name);
    });
  }

  public static function mapMethodName(name:String):String {
    return 'w_$name';
  }

  static function box(t:FFIType, expr:String, size:Null<String>):String {
    return (switch (t) {
      case Bool: 'lua_pushboolean(L, $expr)';
      case Int: 'lua_pushinteger(L, $expr)';
      case Float: 'lua_pushnumber(L, $expr)';
      case String | Bytes if (size != null): 'lua_pushlstring(L, $expr, $size)';
      case String | Bytes: 'lua_pushstring(L, $expr)';
      case SameSizeAs(t, _): box(t, expr, size);
      case _: trace(t); throw "!";
    });
  }

  static function unbox(t:FFIType, i:Int):String {
    return (switch (t) {
      case Void: null;
      case Bool: 'lua_toboolean(L, $i)';
      case Int: 'lua_tointeger(L, $i)';
      case Float: 'lua_tonumber(L, $i)';
      case String: 'lua_tostring(L, $i)';
      case Bytes: 'lua_tostring(L, $i)';
      case NoSize(t): unbox(t, i);
      case SizeOf(_): 'lua_tointeger(L, $i)';
      case SizeOfReturn: "0";
      case _: throw "!";
    });
  }

  static function generateMethod(method:FFIMethod):Void {
    lb.ai('static int ${mapMethodName(method.name)}(lua_State *L) {\n');
    lb.indent(() -> {
      var sizeOfReturn = null;
      for (i in 0...method.args.length) {
        if (method.args[i] == SizeOfReturn)
          sizeOfReturn = 'arg_$i';
        var unboxed = unbox(method.args[i], i);
        if (unboxed == null)
          continue;
        lb.ai('${mapTypeC(method.args[i], 'arg_$i')} = ${unbox(method.args[i], i + 1)};\n');
      }
      if (method.cPrereturn != null)
        lb.ai('${method.cPrereturn}\n');
      var call = '${method.native}(' + [ for (i in 0...method.args.length) switch (method.args[i]) {
        case SizeOfReturn: '&arg_$i';
        case _: 'arg_$i';
      } ].join(", ") + ')';
      if (method.ret != Void)
        lb.ai('${mapTypeC(method.ret, 'ret')} = ');
      if (method.cReturn != null)
        lb.ai('${method.cReturn.replace("%CALL", call)};\n');
      else if (method.ret != Void)
        lb.a('$call;\n');
      else
        lb.ai('$call;\n');
      if (method.ret == Void)
        lb.ai("return 0;\n");
      else {
        lb.ai(box(method.ret, "ret", sizeOfReturn));
        lb.a(";\n");
        lb.ai("return 1;\n");
      }
    });
    lb.ai("}\n");
  }

  static function generateInit(ctx:AmmerContext):Void {
    lb.ai("#ifdef __cplusplus\n");
    lb.ai("extern \"C\" {\n");
    lb.ai("#endif\n");
    lb.ai('int g_init_${ctx.index}(lua_State *L) {\n');
    lb.indent(() -> {
      lb.ai("luaL_Reg wrap[] = {\n");
      lb.indent(() -> {
        for (method in ctx.ffiMethods) {
          lb.ai('{"${mapMethodName(method.name)}", ${mapMethodName(method.name)}},\n');
        }
        lb.ai("{NULL, NULL}");
      });
      lb.ai("};\n");
      lb.ai("lua_newtable(L);\n");
      lb.ai("luaL_setfuncs(L, wrap, 0);\n");
      lb.ai("return 1;\n");
    });
    lb.ai("}\n");
    lb.ai("#ifdef __cplusplus\n");
    lb.ai("}\n");
    lb.ai("#endif\n");
  }

  public static function generate(config:Config, library:AmmerLibraryConfig):Void {
    StubLua.library = library;
    lb = new LineBuf();
    generateHeader();
    var generated:Map<String, Bool> = [];
    for (ctx in library.contexts) {
      for (method in ctx.ffiMethods) {
        if (generated.exists(method.name))
          continue; // TODO: make sure the field has the same signature
        generated[method.name] = true;
        generateMethod(method);
      }
      // generateVariables(ctx);
      generateInit(ctx);
    }
    Utils.update('${config.lua.build}/ammer_${library.name}.lua.${library.abi == Cpp ? "cpp" : "c"}', lb.dump());
  }
}
