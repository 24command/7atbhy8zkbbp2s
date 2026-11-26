// Included after Map/add/flag. Also compiled verbatim by the fake managed adapter.
// One private material per Map. Keep/Destroy the material, never the resource
// shader. A missing/type-mismatched/unsupported shader is a hard acquisition error.
Handle additiveMaterial(Map &m) {
    if (m.additiveMaterial) return m.additiveMaterial;
    auto &r=m.r;
    P shaderType=r.type("UnityEngine","Shader");
    P shader=r.stat(r.type("UnityEngine","Resources"),"Load",{"System.String","System.Type"},
        {r.string_new(blend::shaderResource),r.type_get_object(r.class_get_type(shaderType))});
    if (!r.alive(shader) || r.object_get_class(shader)!=shaderType)
        throw std::runtime_error("Map additive blend: missing Shader resource shaders/trueshadow-additive");
    if (!r.unbox<bool>(r.call(shader,"get_isSupported")))
        throw std::runtime_error("Map additive blend: shaders/trueshadow-additive is unsupported");
    Handle shaderHandle=m.keep(shader); // GC root only; never Destroy the retail asset.
    P material=r.object_new(r.type("UnityEngine","Material"));
    Handle owned=m.keep(material);
    m.assets.push_back(owned);
    r.call(material,".ctor",{"UnityEngine.Shader"},{m.get(shaderHandle)});
    if (!r.alive(material) || r.call(material,"get_shader")!=shader)
        throw std::runtime_error("Map additive blend: material shader binding failed");
    m.additiveMaterial=owned;
    return owned;
}
void bindAdditive(Map &m, blend::Layer &layer, Handle childObject, Handle graphic) {
    Handle material=additiveMaterial(m);
    layer.graphic=graphic;
    layer.group=m.keep(add(m.r,m.get(childObject),"UnityEngine","CanvasGroup"));
    float zero=0;
    // Set zero BEFORE ignoring ancestor groups: no covered/preflight flash.
    m.r.call(m.get(layer.group),"set_alpha",{"System.Single"},{&zero});
    flag(m.r,m.get(layer.group),"set_blocksRaycasts",false);
    flag(m.r,m.get(layer.group),"set_interactable",false);
    flag(m.r,m.get(layer.group),"set_ignoreParentGroups",true);
    float white[]={1,1,1,1};
    m.r.call(m.get(graphic),"set_color",{"UnityEngine.Color"},{white});
    m.r.call(m.get(graphic),"set_material",{"UnityEngine.Material"},{m.get(material)});
    m.hasAdditive=true;
}
void syncAdditive(Map &m, Item &item) {
    if (!item.additive.group) return;
    float alpha=blend::groupAlpha(item.inheritedAlpha,item.additive.tintAlpha,m.rootOpacity,item.active);
    if (alpha!=item.additive.alpha) {
        m.r.call(m.get(item.additive.group),"set_alpha",{"System.Single"},{&alpha});
        item.additive.alpha=alpha;
    }
    // ignoreParentGroups also bypasses input flags, so mirror root/author gates.
    bool input=m.input && item.active && !item.locked && m.rootOpacity>0 && item.inheritedAlpha>.01f;
    if (input!=item.additive.input) {
        flag(m.r,m.get(item.additive.group),"set_blocksRaycasts",input);
        flag(m.r,m.get(item.additive.group),"set_interactable",input);
        item.additive.input=input;
    }
}
void hideAdditive(Map &m) {
    if (!m.hasAdditive) return;
    for (auto &item:m.items) {
        if (!item.additive.group) continue;
        if (item.additive.alpha!=0) {
            float zero=0;
            m.r.call(m.get(item.additive.group),"set_alpha",{"System.Single"},{&zero});
            item.additive.alpha=0;
        }
        if (item.additive.input) {
            flag(m.r,m.get(item.additive.group),"set_blocksRaycasts",false);
            flag(m.r,m.get(item.additive.group),"set_interactable",false);
            item.additive.input=false;
        }
    }
}
void setRootOpacity(Map &m, float alpha) {
    m.rootOpacity=blend::unit(alpha);
    m.r.call(m.get(m.rootGroup),"set_alpha",{"System.Single"},{&m.rootOpacity});
    if (m.hasAdditive) for (auto &item:m.items) syncAdditive(m,item);
}
