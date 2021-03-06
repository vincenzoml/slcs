open Color.Rgb

module type LANG = sig
  type syntax
  type semantics
  val string_of : syntax -> string
  val sem : syntax -> semantics
end

module Logic ( Prop : LANG) = struct
  type 'a formula = 
    T 
  | Prop of 'a
  | Not of 'a formula 
  | And of ('a formula * 'a formula) 
  | Closure of ('a formula) 
  | Until of ('a formula * 'a formula)
      
  module Env = Map.Make(String)

  type fsyntax =
    TRUE 
  | FALSE
  | PROP of Prop.syntax
  | NOT of fsyntax
  | AND of (fsyntax * fsyntax)
  | OR of (fsyntax * fsyntax)
  | CLOS of fsyntax
  | CLOSN of (int * fsyntax)
  | INT of fsyntax
  | UNTIL of (fsyntax * fsyntax)
  | CALL of string * (fsyntax list) 
      
  let rec string_of_fsyntax f =
    match f with
      TRUE -> "T"
    | FALSE -> "F"
    | PROP prop -> Prop.string_of prop
    | NOT f -> Printf.sprintf "!(%s)" (string_of_fsyntax f)
    | AND (f1,f2) -> Printf.sprintf "(%s & %s)" (string_of_fsyntax f1) (string_of_fsyntax f2) 
    | OR (f1,f2) -> Printf.sprintf "(%s | %s)" (string_of_fsyntax f1) (string_of_fsyntax f2) 
    | CLOS f -> Printf.sprintf "(C %s)" (string_of_fsyntax f)
    | CLOSN (i,f) -> Printf.sprintf "(C^%d %s)" i (string_of_fsyntax f)
    | INT f -> Printf.sprintf "(I %s)" (string_of_fsyntax f)
    | UNTIL (f1,f2) -> Printf.sprintf "(%s U %s)" (string_of_fsyntax f1) (string_of_fsyntax f2) 
    | CALL (f,args) -> Printf.sprintf "%s%s" f (string_of_arglist args)
      
  and string_of_arglist args =
    match args with 
      [] -> ""
    | _ -> Printf.sprintf "(%s)" (string_of_arglist_inner args)
      
  and string_of_arglist_inner args =
    match args with 
      [] -> ""
    | [x] -> string_of_fsyntax x
    | x::xs -> Printf.sprintf "%s,%s" (string_of_fsyntax x) (string_of_arglist_inner xs)
      
  let rec fsyntax_sub f fsyntax =
    match fsyntax with
      CALL (ide,arglist) -> f ide
    | x -> x
      
  let rec zipenv env l1 l2 =
    match (l1,l2) with
      ([],[]) -> env
    | (x::xs,y::ys) -> Env.add x (fun [] -> y) (zipenv env xs ys)
    | _ -> raise (Failure "zipenv")
      
  type 'a myfun = 'a formula list -> 'a formula
    
  let rec fun_of_decl ide (env : 'a myfun Env.t) (formalargs : string list) (body : fsyntax) (actualargs : 'a formula list) =
    let newenv =
      try
	zipenv env formalargs actualargs
      with _ -> failwith (Printf.sprintf "wrong number of arguments in call to %s" ide) in
    formula_of_fsyntax newenv body
      
  and formula_of_fsyntax (env : 'a myfun Env.t) (fsyntax : fsyntax) =
    match fsyntax with
      PROP prop -> Prop (Prop.sem prop)
    | TRUE -> T
    | FALSE -> Not T
    | NOT t -> Not (formula_of_fsyntax env t)
    | AND (t1,t2) -> And (formula_of_fsyntax env t1,formula_of_fsyntax env t2)
    | OR (t1,t2) -> Not (And (Not (formula_of_fsyntax env t1), Not (formula_of_fsyntax env t2)))
    | CLOS t -> Closure (formula_of_fsyntax env t)
    | CLOSN (n,t) -> if n <= 0 then (formula_of_fsyntax env t) else Closure (formula_of_fsyntax env (CLOSN(n-1,t)))
    | INT t -> Not (Closure (Not (formula_of_fsyntax env t)))
    | UNTIL (t1,t2) -> Until (formula_of_fsyntax env t1,formula_of_fsyntax env t2)
    | CALL (ide,arglist) -> 
      try (Env.find ide env) (List.map (formula_of_fsyntax env) arglist)
      with _ -> failwith (Printf.sprintf "Unbound identifier: %s" ide)
	
  type syntax = 
    CHECK of fsyntax
  | LET of string * (string list) * fsyntax
end

module Graph = struct
  type syntax = string
  type semantics = string 
  let string_of x = x
  let sem x = x
end

module GraphLogic = Logic(Graph)

module ModelChecker (Point : Set.OrderedType) =
struct
  open GraphLogic

  module PSet = Set.Make(Point)
  type pointSet = PSet.t
  type point = PSet.elt

  type space = {
    points : pointSet;
    post : point -> pointSet;
    pre : point -> pointSet;
    clos : pointSet -> pointSet;
  }
    
  type 'a model = {
    space : space;
    eval : 'a -> pointSet;
  }
 
  let rec check model formula =
    match formula with
      T -> model.space.points
    | Prop p -> model.eval p
    | Not f -> PSet.diff model.space.points (check model f)
    | And (f1,f2) -> PSet.inter (check model f1) (check model f2)
    | Closure f -> model.space.clos (check model f)
    | Until (f1,f2) -> check_until model f1 f2 

  and check_until model f1 f2 =
    let (p,q) = (check model f1, check model f2) in
    let r = ref p in
    let pORq = PSet.union p q in
    let t = ref (PSet.diff (model.space.clos pORq) pORq) in
    while not (PSet.is_empty (!t)) do
      let x = PSet.choose (!t) in
      let n = PSet.diff (PSet.inter (model.space.pre x) (!r)) q in
      r := PSet.diff (!r) n;
      t := PSet.diff (PSet.union (!t) n) (PSet.singleton x)
    done;
    (!r)      
end

module DigitalPlane = ModelChecker (struct 
  type t = (int * int) 
  let compare = Pervasives.compare 
end) 

module GraphMC = ModelChecker (struct
  type t = (int * int) 
  let compare = Pervasives.compare
end)
