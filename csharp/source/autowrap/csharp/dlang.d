module autowrap.csharp.dlang;

import scriptlike : interp, _interp_text;

import std.datetime : Date, DateTime, SysTime, TimeOfDay, TimeZone;
import std.ascii : newline;
import std.meta : allSatisfy;
import std.range.primitives;

import autowrap.csharp.boilerplate;
import autowrap.reflection : isModule, PrimordialType;

enum string methodSetup = "        auto attachThread = AttachThread.create();";


// Wrap global functions from multiple modules
public string wrapDLang(Modules...)() if(allSatisfy!(isModule, Modules)) {
    import autowrap.csharp.common : isDateTimeType, verifySupported;
    import autowrap.reflection : AllAggregates;

    import std.algorithm.iteration : map;
    import std.algorithm.sorting : sort;
    import std.array : array;
    import std.format : format;
    import std.meta : AliasSeq;
    import std.traits : fullyQualifiedName;

    string ret;
    string[] imports = [Modules].map!(a => a.name)().array();

    static foreach(T; AliasSeq!(string, wstring, dstring,
                                bool, byte, ubyte, short, ushort, int, uint, long, ulong, float, double,
                                Marshalled_Duration, Marshalled_std_datetime_date, Marshalled_std_datetime_systime)) {
        ret ~= generateSliceMethods!T(imports);
    }

    static foreach(Agg; AllAggregates!Modules)
    {
        static if(verifySupported!Agg && !isDateTimeType!Agg)
        {
            ret ~= generateSliceMethods!Agg(imports);
            ret ~= generateConstructors!Agg(imports);
            ret ~= generateMethods!Agg(imports);
            ret ~= generateFields!Agg(imports);
        }
    }

    ret ~= generateFunctions!Modules(imports);

    string top = "import autowrap.csharp.boilerplate : AttachThread;" ~ newline;

    foreach(i; sort(imports))
        top ~= format("import %s;%s", i, newline);

    return top ~ "\n" ~ ret;
}

// This is to deal with the cases where the parameter name is the same as a
// module or pacakage name, which results in errors if the full path name is
// used inside the function (e.g. in the return type is prefix.Prefix, and the
// parameter is named prefix).
private enum AdjParamName(string paramName) = paramName ~ "_param";

private string generateConstructors(T)(ref string[] imports)
{
    import autowrap.csharp.common : getDLangInterfaceName, numDefaultArgs, verifySupported;

    import std.algorithm.comparison : among;
    import std.conv : to;
    import std.format : format;
    import std.meta : Filter, staticMap;
    import std.traits : fullyQualifiedName, hasMember, Parameters, ParameterIdentifierTuple;

    string ret;
    alias fqn = getDLangInterfaceType!T;

    //Generate constructor methods
    static if(hasMember!(T, "__ctor") && __traits(getProtection, __traits(getMember, T, "__ctor")).among("export", "public"))
    {
        foreach(i, c; __traits(getOverloads, T, "__ctor"))
        {
            if (__traits(getProtection, c).among("export", "public"))
            {
                alias paramNames = staticMap!(AdjParamName, ParameterIdentifierTuple!c);
                alias ParamTypes = Parameters!c;

                static if(Filter!(verifySupported, ParamTypes).length != ParamTypes.length)
                    continue;
                addImports!ParamTypes(imports);

                static foreach(nda; 0 .. numDefaultArgs!c + 1)
                {{
                    enum numParams = ParamTypes.length - nda;
                    enum interfaceName = format("%s%s_%s", getDLangInterfaceName(fqn, "__ctor"), i, numParams);

                    string exp = "extern(C) export ";
                    exp ~= mixin(interp!"returnValue!(${fqn}) ${interfaceName}(");

                    static foreach(pc; 0 .. paramNames.length - nda)
                        exp ~= mixin(interp!"${getDLangInterfaceType!(ParamTypes[pc])} ${paramNames[pc]}, ");

                    if (numParams != 0)
                        exp = exp[0 .. $ - 2];

                    exp ~= ") nothrow {" ~ newline;
                    exp ~= "    try {" ~ newline;
                    exp ~= methodSetup ~ newline;
                    if (is(T == class))
                    {
                        exp ~= mixin(interp!"        ${fqn} __temp__ = new ${fqn}(");

                        static foreach(pc; 0 .. numParams)
                            exp ~= mixin(interp!"${paramNames[pc]}, ");

                        if (numParams != 0)
                            exp = exp[0 .. $ - 2];

                        exp ~= ");" ~ newline;
                        exp ~= "        pinPointer(cast(void*)__temp__);" ~ newline;
                        exp ~= mixin(interp!"        return returnValue!(${fqn})(__temp__);${newline}");
                    }
                    else if (is(T == struct))
                    {
                        exp ~= mixin(interp!"        return returnValue!(${fqn})(${fqn}(");

                        foreach(pn; paramNames)
                            exp ~= mixin(interp!"${pn}, ");

                        if (numParams != 0)
                            exp = exp[0 .. $ - 2];

                        exp ~= "));" ~ newline;
                    }

                    exp ~= "    } catch (Exception __ex__) {" ~ newline;
                    exp ~= mixin(interp!"        return returnValue!(${fqn})(__ex__);${newline}");
                    exp ~= "    }" ~ newline;
                    exp ~= "}" ~ newline;
                    ret ~= exp;
                }}
            }
        }
    }

    return ret;
}

private string generateMethods(T)(ref string[] imports)
{
    import autowrap.csharp.common : isDateTimeType, isDateTimeArrayType, getDLangInterfaceName,
                                    numDefaultArgs, verifySupported;

    import std.algorithm.comparison : among;
    import std.format : format;
    import std.meta : AliasSeq, Filter, staticMap;
    import std.traits : isFunction, fullyQualifiedName, ReturnType, Parameters, ParameterIdentifierTuple;

    string ret;
    alias fqn = getDLangInterfaceType!T;

    foreach(m; __traits(allMembers, T))
    {
        static if (!m.among("__ctor", "toHash", "opEquals", "opCmp", "factory") &&
                   is(typeof(__traits(getMember, T, m))))
        {
            foreach(oc, mo; __traits(getOverloads, T, m))
            {
                static if(isFunction!mo && __traits(getProtection, mo).among("export", "public"))
                {
                    alias RT = ReturnType!mo;
                    alias returnTypeStr = getDLangInterfaceType!RT;
                    alias ParamTypes = Parameters!mo;
                    alias paramNames = staticMap!(AdjParamName, ParameterIdentifierTuple!mo);
                    alias Types = AliasSeq!(RT, ParamTypes);

                    static if(Filter!(verifySupported, Types).length != Types.length)
                        continue;
                    else
                    {
                        addImports!Types(imports);

                        static foreach(nda; 0 .. numDefaultArgs!mo + 1)
                        {{
                            enum numParams = ParamTypes.length - nda;
                            enum interfaceName = format("%s%s_%s", getDLangInterfaceName(fqn, m), oc, numParams);

                            string exp = "extern(C) export ";

                            static if (!is(RT == void))
                                exp ~= mixin(interp!"returnValue!(${returnTypeStr})");
                            else
                                exp ~= "returnVoid";

                            exp ~= mixin(interp!" ${interfaceName}(");

                            if (is(T == struct))
                                exp ~= mixin(interp!"ref ${fqn} __obj__, ");
                            else
                                exp ~= mixin(interp!"${fqn} __obj__, ");

                            static foreach(pc; 0 .. numParams)
                                exp ~= mixin(interp!"${getDLangInterfaceType!(ParamTypes[pc])} ${paramNames[pc]}, ");

                            exp = exp[0 .. $ - 2];
                            exp ~= ") nothrow {" ~ newline;
                            exp ~= "    try {" ~ newline;
                            exp ~= methodSetup ~ newline;
                            exp ~= "        ";

                            if (!is(RT == void))
                                exp ~= "auto __result__ = ";

                            exp ~= mixin(interp!"__obj__.${m}(");

                            static foreach(pc; 0 .. numParams)
                                exp ~= mixin(interp!"${generateParameter!(ParamTypes[pc])(paramNames[pc])}, ");

                            if (numParams != 0)
                                exp = exp[0 .. $ - 2];

                            exp ~= ");" ~ newline;

                            static if (isDateTimeType!RT || isDateTimeArrayType!RT)
                                exp ~= mixin(interp!"        return returnValue!(${returnTypeStr})(${generateReturn!RT(\"__result__\")});${newline}");
                            else static if (!is(RT == void))
                                exp ~= mixin(interp!"        return returnValue!(${returnTypeStr})(__result__);${newline}");
                            else
                                exp ~= "        return returnVoid();" ~ newline;

                            exp ~= "    } catch (Exception __ex__) {" ~ newline;

                            if (!is(RT == void))
                                exp ~= mixin(interp!"        return returnValue!(${returnTypeStr})(__ex__);${newline}");
                            else
                                exp ~= "        return returnVoid(__ex__);" ~ newline;

                            exp ~= "    }" ~ newline;
                            exp ~= "}" ~ newline;
                            ret ~= exp;
                        }}
                    }
                }
            }
        }
    }

    return ret;
}

private string generateFields(T)(ref string[] imports) {
    import autowrap.csharp.common : getDLangInterfaceName, verifySupported;

    import std.traits : fullyQualifiedName, Fields, FieldNameTuple;
    import std.algorithm: among;

    string ret;
    alias fqn = getDLangInterfaceType!T;
    if (is(T == class) || is(T == interface))
    {
        alias FieldTypes = Fields!T;
        alias fieldNames = FieldNameTuple!T;
        static foreach(fc; 0 .. FieldTypes.length)
        {{
            alias FT = FieldTypes[fc];
            static if(verifySupported!FT && __traits(getProtection, __traits(getMember,T,fieldNames[fc])).among("export", "public"))
            {
                enum fn = fieldNames[fc];
                static if (is(typeof(__traits(getMember, T, fn))))
                {
                    addImport!FT(imports);

                    ret ~= mixin(interp!"extern(C) export returnValue!(${getDLangInterfaceType!FT}) ${getDLangInterfaceName(fqn, fn ~ \"_get\")}(${fqn} __obj__) nothrow {${newline}");
                    ret ~= generateMethodErrorHandling(mixin(interp!"        auto __value__ = __obj__.${fn};${newline}        return returnValue!(${getDLangInterfaceType!FT})(${generateReturn!FT(\"__value__\")});"), mixin(interp!"returnValue!(${getDLangInterfaceType!FT})"));
                    ret ~= "}" ~ newline;
                    ret ~= mixin(interp!"extern(C) export returnVoid ${getDLangInterfaceName(fqn, fn ~ \"_set\")}(${fqn} __obj__, ${getDLangInterfaceType!FT} value) nothrow {${newline}");
                    ret ~= generateMethodErrorHandling(mixin(interp!"        __obj__.${fn} = ${generateParameter!FT(\"value\")};${newline}        return returnVoid();"), "returnVoid");
                    ret ~= "}" ~ newline;
                }
            }
        }}
    }
    return ret;
}

private string generateFunctions(Modules...)(ref string[] imports)
    if(allSatisfy!(isModule, Modules))
{
    import autowrap.csharp.common : getDLangInterfaceName, numDefaultArgs, verifySupported;
    import autowrap.reflection: AllFunctions;

    import std.format : format;
    import std.meta : AliasSeq, Filter, staticMap;
    import std.traits : fullyQualifiedName, hasMember, functionAttributes, FunctionAttribute,
                        ReturnType, Parameters, ParameterIdentifierTuple;

    string ret;

    foreach(func; AllFunctions!Modules)
    {
        foreach(oc, overload; __traits(getOverloads, func.module_, func.name))
        {
            alias RT = ReturnType!overload;
            alias ParamTypes = Parameters!overload;
            alias Types = AliasSeq!(RT, ParamTypes);

            static if(Filter!(verifySupported, Types).length != Types.length)
                continue;
            else
            {
                addImports!Types(imports);

                static foreach(nda; 0 .. numDefaultArgs!overload + 1)
                {{
                    enum numParams = ParamTypes.length - nda;
                    enum interfaceName = format("%s%s_%s", getDLangInterfaceName(func.moduleName, null, func.name), oc, numParams);
                    alias returnTypeStr = getDLangInterfaceType!RT;
                    alias paramNames = staticMap!(AdjParamName, ParameterIdentifierTuple!overload);

                    static if (!is(RT == void))
                        string retType = mixin(interp!"returnValue!(${returnTypeStr})");
                    else
                        string retType = "returnVoid";

                    string funcStr = "extern(C) export ";
                    funcStr ~= mixin(interp!"${retType} ${interfaceName}(");

                    static foreach(pc; 0 .. numParams)
                        funcStr ~= mixin(interp!"${getDLangInterfaceType!(ParamTypes[pc])} ${paramNames[pc]}, ");

                    if(numParams != 0)
                        funcStr = funcStr[0 .. $ - 2];

                    funcStr ~= ") nothrow {" ~ newline;
                    funcStr ~= "    try {" ~ newline;
                    funcStr ~= methodSetup ~ newline;
                    funcStr ~= "        ";

                    if (!is(RT == void))
                        funcStr ~= mixin(interp!"auto __return__ = ${func.name}(");
                    else
                        funcStr ~= mixin(interp!"${func.name}(");

                    static foreach(pc; 0 .. numParams)
                        funcStr ~= mixin(interp!"${generateParameter!(ParamTypes[pc])(paramNames[pc])}, ");

                    if(numParams != 0)
                        funcStr = funcStr[0 .. $ - 2];

                    funcStr ~= ");" ~ newline;

                    if (!is(RT == void))
                        funcStr ~= mixin(interp!"        return ${retType}(${generateReturn!RT(\"__return__\")});${newline}");
                    else
                        funcStr ~= mixin(interp!"        return ${retType}();${newline}");

                    funcStr ~= "    } catch (Exception __ex__) {" ~ newline;
                    funcStr ~= mixin(interp!"        return ${retType}(__ex__);${newline}");
                    funcStr ~= "    }" ~ newline;
                    funcStr ~= "}" ~ newline;

                    ret ~= funcStr;
                }}
            }
        }
    }

    return ret;
}

private string generateSliceMethods(T)(ref string[] imports) {
    import autowrap.csharp.common : getDLangSliceInterfaceName;

    import std.traits : fullyQualifiedName, moduleName,  TemplateOf;

    addImport!T(imports);

    alias fqn = getDLangInterfaceType!T;

    //Generate slice creation method
    string ret = mixin(interp!"extern(C) export returnValue!(${fqn}[]) ${getDLangSliceInterfaceName(fqn, \"Create\")}(size_t capacity) nothrow {${newline}");
    ret ~= generateMethodErrorHandling(mixin(interp!"        ${fqn}[] __temp__;${newline}        __temp__.reserve(capacity);${newline}        pinPointer(cast(void*)__temp__.ptr);${newline}        return returnValue!(${fqn}[])(__temp__);"), mixin(interp!"returnValue!(${fqn}[])"));
    ret ~= "}" ~ newline;

    //Generate slice method
    ret ~= mixin(interp!"extern(C) export returnValue!(${fqn}[]) ${getDLangSliceInterfaceName(fqn, \"Slice\")}(${fqn}[] slice, size_t begin, size_t end) nothrow {${newline}");
    ret ~= generateMethodErrorHandling(mixin(interp!"        ${fqn}[] __temp__ = slice[begin..end];${newline}        pinPointer(cast(void*)__temp__.ptr);${newline}        return returnValue!(${fqn}[])(__temp__);"), mixin(interp!"returnValue!(${fqn}[])"));
    ret ~= "}" ~ newline;

    //Generate get method
    ret ~= mixin(interp!"extern(C) export returnValue!(${fqn}) ${getDLangSliceInterfaceName(fqn, \"Get\")}(${fqn}[] slice, size_t index) nothrow {${newline}");
    ret ~= generateMethodErrorHandling(mixin(interp!"        return returnValue!(${fqn})(slice[index]);"), mixin(interp!"returnValue!(${fqn})"));
    ret ~= "}" ~ newline;

    //Generate set method
    ret ~= mixin(interp!"extern(C) export returnVoid ${getDLangSliceInterfaceName(fqn, \"Set\")}(${fqn}[] slice, size_t index, ${fqn} set) nothrow {${newline}");
    ret ~= generateMethodErrorHandling(mixin(interp!"        slice[index] = set;${newline}        return returnVoid();"), "returnVoid");
    ret ~= "}" ~ newline;

    //Generate item append method
    ret ~= mixin(interp!"extern(C) export returnValue!(${fqn}[]) ${getDLangSliceInterfaceName(fqn, \"AppendValue\")}(${fqn}[] slice, ${fqn} append) nothrow {${newline}");
    ret ~= generateMethodErrorHandling(mixin(interp!"        return returnValue!(${fqn}[])(slice ~= append);"), mixin(interp!"returnValue!(${fqn}[])"));
    ret ~= "}" ~ newline;

    //Generate slice append method
    ret ~= mixin(interp!"extern(C) export returnValue!(${fqn}[]) ${getDLangSliceInterfaceName(fqn, \"AppendSlice\")}(${fqn}[] slice, ${fqn}[] append) nothrow {${newline}");
    ret ~= generateMethodErrorHandling(mixin(interp!"        return returnValue!(${fqn}[])(slice ~= append);"), mixin(interp!"returnValue!(${fqn}[])"));
    ret ~= "}" ~ newline;

    return ret;
}

private string generateMethodErrorHandling(string insideCode, string returnType) {
    string ret = "    try {" ~ newline;
    ret ~= methodSetup ~ newline;
    ret ~= insideCode ~ newline;
    ret ~= "    } catch (Exception __ex__) {" ~ newline;
    ret ~= mixin(interp!"        return ${returnType}(__ex__);${newline}");
    ret ~= "    }" ~ newline;
    return ret;
}

private string generateParameter(T)(string name) {

    import autowrap.csharp.common : isDateTimeType, isDateTimeArrayType;
    import std.format : format;
    import std.traits : fullyQualifiedName;

    alias fqn = fullyQualifiedName!(PrimordialType!T);

    static if (isDateTimeType!T)
        return format!"cast(%s)%s"(fqn, name);
    else static if (isDateTimeArrayType!T)
        return format!"mapArray!(a => cast(%s)a)(%s)"(fqn, name);
    else
        return name;
}

private string generateReturn(T)(string name) {

    import autowrap.csharp.boilerplate : Marshalled_Duration, Marshalled_std_datetime_date, Marshalled_std_datetime_systime;
    import core.time : Duration;
    import std.datetime.date : Date, DateTime, TimeOfDay;
    import std.datetime.systime : SysTime;
    import std.format : format;
    import std.traits : fullyQualifiedName, Unqual;

    alias U = Unqual!T;

    // FIXME This code really should be reworked so that there's no need to
    // check for arrays of date/time types but rather it's part of the general
    // array handling.
    static if(is(U == Duration))
        return format!"Marshalled_Duration(%s)"(name);
    else static if(is(U == DateTime) || is(U == Date) || is(U == TimeOfDay))
        return format!"Marshalled_std_datetime_date(%s)"(name);
    else static if(is(U == SysTime))
        return format!"Marshalled_std_datetime_systime(%s)"(name);
    else static if(is(U == Duration[]))
        return format!"mapArray!(a => Marshalled_Duration(a))(%s)"(name);
    else static if(is(U == DateTime[]) || is(U == Date[]) || is(U == TimeOfDay[]))
        return format!"mapArray!(a => Marshalled_std_datetime_date(a))(%s)"(name);
    else static if(is(U == SysTime[]))
        return format!"mapArray!(a => Marshalled_std_datetime_systime(a))(%s)"(name);
    else
        return name;
}

private void addImports(T...)(ref string[] imports)
{
    foreach(U; T)
        addImport!U(imports);
}

private void addImport(T)(ref string[] imports)
{
    import std.algorithm.searching : canFind;
    import std.traits : isBuiltinType, isDynamicArray, moduleName;
    import autowrap.csharp.common : isSupportedType;

    static assert(isSupportedType!T, "missing check for supported type");

    static if(isDynamicArray!T)
        addImport!(ElementType!T)(imports);
    else static if(!isBuiltinType!T)
    {
        enum mod = moduleName!T;
        if(!mod.empty && !imports.canFind(mod))
            imports ~= mod;
    }
}

private string getDLangInterfaceType(T)() {

    import core.time : Duration;
    import std.datetime.date : Date, DateTime, TimeOfDay;
    import std.datetime.systime : SysTime;
    import std.traits : fullyQualifiedName, Unqual;

    alias U = Unqual!T;

    // FIXME This code really should be reworked so that there's no need to
    // check for arrays of date/time types, but rather it's part of the general
    // array handling.
    static if(is(U == Duration))
        return "Marshalled_Duration";
    else static if(is(U == DateTime) || is(U == Date) || is(U == TimeOfDay))
        return "Marshalled_std_datetime_date";
    else static if(is(U == SysTime))
        return "Marshalled_std_datetime_systime";
    else static if(is(U == Duration[]))
        return "Marshalled_Duration[]";
    else static if(is(U == DateTime[]) || is(U == Date[]) || is(U == TimeOfDay[]))
        return "Marshalled_std_datetime_date[]";
    else static if(is(U == SysTime[]))
        return "Marshalled_std_datetime_systime[]";
    else
        return fullyQualifiedName!T;
}
