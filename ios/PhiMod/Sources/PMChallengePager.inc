static P add(Runtime &r, P go, const char *ns, const char *name) {
    return r.call(go, "AddComponent", {"System.Type"}, {r.type_get_object(r.class_get_type(r.type(ns, name)))});
}
static P pagerLabel(Runtime &r, P parent, P font, const char *name, float x, bool button, V2 requestedSize = {0,0}) {
    P go = r.object_new(r.type("UnityEngine", "GameObject"));
    r.call(go, ".ctor", {"System.String"}, {r.string_new(name)});
    P rect = add(r, go, "UnityEngine", "RectTransform");
    bool no = false;
    r.call(rect, "SetParent", {"UnityEngine.Transform", "System.Boolean"}, {parent, &no});
    int layer = r.unbox<int>(r.call(gameObject(r, parent), "get_layer"));
    r.call(go, "set_layer", {"System.Int32"}, {&layer});
    V2 anchor{0.47f, 1}, size{button ? 80.f : 200.f, 80}, pos{x, -62};
    if(requestedSize.x>0 && requestedSize.y>0) size=requestedSize;
    for (auto method : {"set_anchorMin", "set_anchorMax"}) r.call(rect, method, {"UnityEngine.Vector2"}, {&anchor});
    r.call(rect, "set_sizeDelta", {"UnityEngine.Vector2"}, {&size});
    r.call(rect, "set_anchoredPosition", {"UnityEngine.Vector2"}, {&pos});
    P labelObject = go, polygon = nullptr;
    if (button) {
        polygon = add(r, go, "Lean.Gui", "LeanPolygon");
        float fill = -1, cut = size.y * std::fabs(r.unbox<float>(r.stat(r.type("Phigros.UI","MsgBox"),"get_InverseSlope")));
        r.call(polygon,"set_Thickness",{"System.Single"},{&fill});
        P points = r.call(polygon,"get_Points");
        r.call(points,"Clear");
        struct Corner {float x,y,u,v;};
        for (Corner point : {Corner{cut,0,0,1},Corner{0,0,1,1},Corner{-cut,0,1,0},Corner{0,0,0,0}})
            r.call(points,"Add",{"UnityEngine.Vector4"},{&point});
        r.call(polygon,"SetVerticesDirty");
        labelObject = r.object_new(r.type("UnityEngine","GameObject"));
        r.call(labelObject,".ctor",{"System.String"},{r.string_new("Arrow")});
        r.call(labelObject,"set_layer",{"System.Int32"},{&layer});
        P arrowRect=add(r,labelObject,"UnityEngine","RectTransform");
        r.call(arrowRect,"SetParent",{"UnityEngine.Transform","System.Boolean"},{rect,&no});
        V2 zero{0,0},full{1,1};
        r.call(arrowRect,"set_anchorMin",{"UnityEngine.Vector2"},{&zero});
        r.call(arrowRect,"set_anchorMax",{"UnityEngine.Vector2"},{&full});
        r.call(arrowRect,"set_offsetMin",{"UnityEngine.Vector2"},{&zero});
        r.call(arrowRect,"set_offsetMax",{"UnityEngine.Vector2"},{&zero});
    }
    P label = add(r, labelObject, "UnityEngine.UI", "Text");
    r.call(label, "set_font", {"UnityEngine.Font"}, {font});
    int fontSize = 32, center = 4;
    r.call(label, "set_fontSize", {"System.Int32"}, {&fontSize});
    r.call(label, "set_alignment", {"UnityEngine.TextAnchor"}, {&center});
    r.call(label, "set_raycastTarget", {"System.Boolean"}, {&no});
    if (!button) return label;
    r.text(label, name);
    P control = add(r, go, "UnityEngine.UI", "Button");
    r.call(control, "set_targetGraphic", {"UnityEngine.UI.Graphic"}, {polygon});
    return control;
}

