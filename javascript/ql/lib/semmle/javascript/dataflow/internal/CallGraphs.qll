/**
 * Internal predicates for computing the call graph.
 */

private import javascript
private import semmle.javascript.dataflow.internal.StepSummary
private import semmle.javascript.dataflow.internal.PreCallGraphStep

cached
module CallGraph {
  /** Gets the function referenced by `node`, as determined by the type inference. */
  cached
  Function getAFunctionValue(AnalyzedNode node) {
    result = node.getAValue().(AbstractCallable).getFunction()
  }

  /** Holds if the type inferred for `node` is indefinite due to global flow. */
  cached
  predicate isIndefiniteGlobal(AnalyzedNode node) {
    node.analyze().getAValue().isIndefinite("global")
  }

  /**
   * Gets a data flow node that refers to the given function.
   *
   * Note that functions are not currently type-tracked, but this exposes the type-tracker `t`
   * from underlying class tracking if the function came from a class or instance.
   */
  pragma[nomagic]
  private DataFlow::SourceNode getAFunctionReference(
    DataFlow::FunctionNode function, int imprecision, DataFlow::TypeTracker t
  ) {
    t.start() and
    exists(Function fun |
      fun = function.getFunction() and
      fun = getAFunctionValue(result)
    |
      if isIndefiniteGlobal(result)
      then
        fun.getFile() = result.getFile() and imprecision = 0
        or
        fun.inExternsFile() and imprecision = 1
        or
        imprecision = 2
      else imprecision = 0
    )
    or
    imprecision = 0 and
    t.start() and
    AccessPath::step(function, result)
    or
    t.start() and
    imprecision = 0 and
    PreCallGraphStep::step(any(DataFlow::Node n | function.flowsTo(n)), result)
    or
    imprecision = 0 and
    result = callgraphStep(function, t)
  }

  /**
   * Gets a reference to `function` type-tracked by `t`.
   *
   * This only includes steps that aren't included in ordinary type-tracking.
   * For example, this steps from a method definition to an access on an instance, but
   * does not step through access paths, as those are included in type-tracking already.
   */
  cached
  DataFlow::SourceNode callgraphStep(DataFlow::FunctionNode function, DataFlow::TypeTracker t) {
    exists(DataFlow::ClassNode cls |
      exists(string name |
        function = cls.getInstanceMethod(name) and
        cls.getAnInstanceMemberAccess(name, t.continue()) = result
        or
        function = cls.getStaticMethod(name) and
        cls.getAClassReference(t.continue()).getAPropertyRead(name) = result
      )
      or
      function = cls.getConstructor() and
      cls.getAClassReference(t.continue()) = result
    )
    or
    exists(DataFlow::ObjectLiteralNode object, string prop |
      function = object.getAPropertySource(prop) and
      result = getAnObjectLiteralRef(object).getAPropertyRead(prop) and
      t.start()
    )
    or
    exists(DataFlow::FunctionNode outer |
      result = getAFunctionReference(outer, 0, t.continue()).getAnInvocation() and
      locallyReturnedFunction(outer, function)
    )
  }

  private predicate locallyReturnedFunction(
    DataFlow::FunctionNode outer, DataFlow::FunctionNode inner
  ) {
    inner.flowsTo(outer.getAReturn())
  }

  /**
   * Gets a data flow node that refers to the given function.
   */
  cached
  DataFlow::SourceNode getAFunctionReference(DataFlow::FunctionNode function, int imprecision) {
    result = getAFunctionReference(function, imprecision, DataFlow::TypeTracker::end())
  }

  /**
   * Gets a data flow node that refers to the result of the given partial function invocation,
   * with `function` as the underlying function.
   */
  pragma[nomagic]
  private DataFlow::SourceNode getABoundFunctionReferenceAux(
    DataFlow::FunctionNode function, int boundArgs, DataFlow::TypeTracker t
  ) {
    exists(DataFlow::PartialInvokeNode partial, DataFlow::Node callback |
      result = partial.getBoundFunction(callback, boundArgs) and
      getAFunctionReference(function, 0, t.continue()).flowsTo(callback)
    )
    or
    exists(StepSummary summary, DataFlow::TypeTracker t2 |
      result = getABoundFunctionReferenceAux(function, boundArgs, t2, summary) and
      t = t2.append(summary)
    )
  }

  pragma[noinline]
  private DataFlow::SourceNode getABoundFunctionReferenceAux(
    DataFlow::FunctionNode function, int boundArgs, DataFlow::TypeTracker t, StepSummary summary
  ) {
    exists(DataFlow::SourceNode prev |
      prev = getABoundFunctionReferenceAux(function, boundArgs, t) and
      StepSummary::step(prev, result, summary)
    )
  }

  /**
   * Gets a data flow node that refers to the result of the given partial function invocation,
   * with `function` as the underlying function.
   */
  cached
  DataFlow::SourceNode getABoundFunctionReference(
    DataFlow::FunctionNode function, int boundArgs, boolean contextDependent
  ) {
    exists(DataFlow::TypeTracker t |
      result = getABoundFunctionReferenceAux(function, boundArgs, t) and
      t.end() and
      contextDependent = t.hasCall()
    )
  }

  /**
   * Gets a possible callee of `node` with the given `imprecision`.
   *
   * Does not include custom call edges.
   */
  cached
  DataFlow::FunctionNode getACallee(DataFlow::InvokeNode node, int imprecision) {
    getAFunctionReference(result, imprecision).flowsTo(node.getCalleeNode())
    or
    imprecision = 0 and
    exists(InvokeExpr expr | expr = node.(DataFlow::Impl::ExplicitInvokeNode).asExpr() |
      result.getFunction() = expr.getResolvedCallee()
      or
      exists(DataFlow::ClassNode cls |
        expr.(SuperCall).getBinder() = cls.getConstructor().getFunction() and
        result = cls.getADirectSuperClass().getConstructor()
      )
    )
  }

  /** Holds if a property setter named `name` exists in a class. */
  private predicate isSetterName(string name) {
    exists(any(DataFlow::ClassNode cls).getInstanceMember(name, DataFlow::MemberKind::setter()))
  }

  /**
   * Gets a property write that assigns to the property `name` on an instance of this class,
   * and `name` is the name of a property setter.
   */
  private DataFlow::PropWrite getAnInstanceMemberAssignment(DataFlow::ClassNode cls, string name) {
    isSetterName(name) and // restrict size of predicate
    result = cls.getAnInstanceReference().getAPropertyWrite(name)
    or
    exists(DataFlow::ClassNode subclass |
      result = getAnInstanceMemberAssignment(subclass, name) and
      not exists(subclass.getInstanceMember(name, DataFlow::MemberKind::setter())) and
      cls = subclass.getADirectSuperClass()
    )
  }

  /**
   * Gets a getter or setter invoked as a result of the given property access.
   */
  cached
  DataFlow::FunctionNode getAnAccessorCallee(DataFlow::PropRef ref) {
    exists(DataFlow::ClassNode cls, string name |
      ref = cls.getAnInstanceMemberAccess(name) and
      result = cls.getInstanceMember(name, DataFlow::MemberKind::getter())
      or
      ref = getAnInstanceMemberAssignment(cls, name) and
      result = cls.getInstanceMember(name, DataFlow::MemberKind::setter())
    )
    or
    exists(DataFlow::ObjectLiteralNode object, string name |
      ref = getAnObjectLiteralRef(object).getAPropertyRead(name) and
      result = object.getPropertyGetter(name)
      or
      ref = getAnObjectLiteralRef(object).getAPropertyWrite(name) and
      result = object.getPropertySetter(name)
    )
  }

  private predicate shouldTrackObjectLiteral(DataFlow::ObjectLiteralNode node) {
    (
      node.getAPropertySource() instanceof DataFlow::FunctionNode
      or
      exists(node.getPropertyGetter(_))
      or
      exists(node.getPropertySetter(_))
    ) and
    not node.getTopLevel().isExterns()
  }

  /**
   * Gets a step summary for tracking object literals.
   *
   * To avoid false flow from callbacks passed in via "named parameters", we only track object
   * literals out of returns, not into calls.
   */
  private StepSummary objectLiteralStep() { result = LevelStep() or result = ReturnStep() }

  /** Gets a node that refers to the given object literal, via a limited form of type tracking. */
  cached
  DataFlow::SourceNode getAnObjectLiteralRef(DataFlow::ObjectLiteralNode node) {
    shouldTrackObjectLiteral(node) and
    result = node
    or
    StepSummary::step(getAnObjectLiteralRef(node), result, objectLiteralStep())
  }
}
