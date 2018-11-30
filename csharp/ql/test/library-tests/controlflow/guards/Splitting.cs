using System;
using System.Diagnostics;

/// <summary>
/// Tests related to CFG splitting.
/// </summary>
public class Splitting
{
    void M1(bool b, object o)
    {
        if (b)
            if (o != null)
                o.ToString(); // null guarded
        if (b)
            o.ToString(); // not null guarded
        o.ToString(); // not null guarded
    }

    string M2(bool b, object o)
    {
        if (b)
            if (o != null)
                return o.ToString(); // null guarded
        if (b)
            o.ToString(); // anti-null guarded
        return o.ToString(); // not null guarded
    }

    string M3(bool b, object o)
    {
        if (b)
            if (o == null)
                return "";
        if (b)
            o.ToString(); // null guarded
        return o.ToString(); // not null guarded
    }

    void M4(bool b, object o)
    {
        if (o != null)
        {
            if (b)
                o.ToString(); // null guarded
            if (b)
                o.ToString(); // null guarded
        }
    }

    string M5(bool b, object o)
    {
        if (b)
            o.ToString(); // not null guarded
        if (o != null)
            o.ToString(); // null guarded
        if (b)
            o.ToString(); // not null guarded
        return o.ToString(); // not null guarded
    }

    string M6(bool b, object o)
    {
        if (b)
            o.ToString(); // not null guarded
        if (o != null)
            return o.ToString(); // null guarded
        if (b)
            o.ToString(); // anti-null guarded
        return o.ToString(); // anti-null guarded
    }

    string M7(bool b, object o, bool b2)
    {
        if (b)
            o.ToString(); // not null guarded
        if (o != null)
            if (b2)
                return o.ToString(); // null guarded
        if (b)
            o.ToString(); // not null guarded
        return o.ToString(); // not null guarded
    }

    void M8(bool b, object o)
    {
        if (b)
            Debug.Assert(o != null);
        o.ToString(); // not null guarded
        if (b)
            o.ToString(); // null guarded
        o.ToString(); // not null guarded
    }

    string M9(bool b, object o)
    {
        if (b)
            Debug.Assert(o == null);
        if (b)
            o.ToString(); // anti-null guarded
        return o.ToString(); // not null guarded
    }

    void M10(bool b, object o)
    {
        Debug.Assert(o != null);
        if (b)
            o.ToString(); // null guarded
        if (b)
            o.ToString(); // null guarded
    }

    string M11(bool b, object o)
    {
        if (b)
            o.ToString(); // not null guarded
        Debug.Assert(o != null);
        o.ToString(); // null guarded
        if (b)
            o.ToString(); // null guarded
        return o.ToString(); // null guarded
    }
}
