package hxbit;
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Type;
using haxe.macro.ExprTools;

abstract class Closure<T> #if !macro implements hxbit.Serializable #end {

	function new() {}
	public abstract function call() : T;

	#if macro

	static function nullPos( e : Expr ) {
		var e = e.map(nullPos);
		e.pos = null;
		return e;
	}

	static function gatherCapturedVars( ctx : { unbound : Map<String,{ v : TVar, p : Position }>, defined : Map<String, Bool> }, e : TypedExpr ) {
		switch( e.expr ) {
		case TLocal(v) if( !ctx.defined.get(v.name) ):
			var prev = ctx.unbound.get(v.name);
			if( prev == null )
				ctx.unbound.set(v.name, { v : v, p : e.pos });
			else if( prev.v.id != v.id )
				Context.error("Duplicate captured var "+v.name, e.pos);
		case TVar(v,e):
			if( e != null ) gatherCapturedVars(ctx, e);
			ctx.defined.set(v.name, true);
		case TFor(v,e1,e2):
			gatherCapturedVars(ctx, e1);
			var prev = ctx.defined.get(v.name);
			ctx.defined.set(v.name, true);
			gatherCapturedVars(ctx, e2);
			ctx.defined.set(v.name, prev);
		case TBlock(el):
			var ctx2 = { unbound : ctx.unbound, defined : ctx.defined.copy() };
			for( e in el )
				gatherCapturedVars(ctx2, e);
		case TSwitch(_), TTry(_):
			Context.error("TODO", e.pos);
		case TFunction(f):
			var ctx2 = { unbound : ctx.unbound, defined : ctx.defined.copy() };
			for( v in f.args )
				ctx2.defined.set(v.v.name, true);
			gatherCapturedVars(ctx2, f.expr);
		default:
			haxe.macro.TypedExprTools.iter(e, gatherCapturedVars.bind(ctx));
		}
	}

	static function replaceVars( ctx : { uid : Int, m : Map<Int,Bool> }, e : TypedExpr ) {
		inline function updateVar(v:TVar) {
			if( !ctx.m.exists(v.id) ) {
				ctx.m.set(v.id, true);
				var name = v.name == "`this" ? "__this" : "__"+ctx.uid++;
				haxe.macro.TypeTools.setVarName(v,name);
			}
		}
		switch( e.expr ) {
		case TVar(v,einit) if( v.name.charCodeAt(0) == '`'.code ):
			updateVar(v);
		case TLocal(v) if( v.name.charCodeAt(0) == '`'.code ):
			updateVar(v);
		default:
		}
		haxe.macro.TypedExprTools.iter(e, replaceVars.bind(ctx));
	}

	#end

	public static macro function make( funExpr : Expr ) {
		var pos = funExpr.pos;
		switch( funExpr.expr ) {
		case EFunction(_,f) if( f.args.length == 0 && f.params.length == 0 ):
			var loc = haxe.macro.PositionTools.toLocation(pos);
			var currentClass = Context.getLocalClass().toString();
			var prefix = currentClass.split(".").join("_");
			prefix = prefix.charAt(0).toUpperCase() + prefix.substr(1) + "_" + Context.getLocalMethod() + "_L" + loc.range.start.line;
			var sign = Context.signature(nullPos(f.expr)).substr(0, 6);
			var ident = prefix + "_"+sign;
			var constructVars : Array<String> = [];
			try {
				Context.getType("hxbit.closure."+ident);
			} catch( err ) {

				var texpr = Context.withOptions({ inlining : false }, () -> Context.typeExpr(funExpr));
				var t = switch( texpr.t ) {
				case TFun(_,t): haxe.macro.TypeTools.toComplexType(t);
				default: throw "assert";
				}

				var unbound = new Map();
				gatherCapturedVars({ unbound : unbound, defined : new Map() }, texpr);
				replaceVars({ uid : 0, m : new Map() },texpr);
				var outExpr = Context.getTypedExpr(switch( texpr.expr ) { case TFunction(f): f.expr; default: throw "assert"; });

				var fields : Array<Field> = [];
				var vars = [];
				for( v in unbound ) {
					var t = haxe.macro.TypeTools.toComplexType(v.v.t);
					var vname = v.v.name, cname = vname;
					if( vname == "`this" ) {
						vname = "__this";
						cname = "this";
					}
					var expr = { expr : EConst(CIdent(vname)), pos : v.p };
					vars.push({ name : vname, type : t, expr : expr });
					fields.push({
						pos : v.p,
						name : vname,
						kind : FVar(t),
						meta: [{ pos : v.p, name : ":s" }],
					});
					constructVars.push(cname);
				}

				//Context.warning(outExpr.toString(), outExpr.pos);

				fields.push({
					pos : pos,
					name : "new",
					access : [APublic],
					kind : FFun({
						args : [for( v in vars ) { name : v.name, type : v.type }],
						expr : {
							expr : EBlock([macro super()].concat([for( v in vars ) { var name = v.name; macro this.$name = ${v.expr}; }])),
							pos : pos
						},
					}),
				});
				fields.push({
					pos : pos,
					name : "call",
					kind : FFun({
						args : [],
						ret : t,
						expr : outExpr,
					}),
				});

				Context.defineType({
					pos : pos,
					name : ident,
					pack : ["hxbit","closure"],
					kind : TDClass({ pack : ["hxbit"], name : "Closure", params : [TPType(t)] }),
					fields : fields,
					meta : [{ name : ":access", pos : pos, params : [macro $p{currentClass.split(".")}] }],
				});
			}
			return { expr : ENew({ pack : ["hxbit","closure"], name : ident },[for( v in constructVars ) macro $i{v}]), pos : pos };
		default:
			Context.error("Expression should be a function with no argument", pos);
			return macro null;
		}
	}

}