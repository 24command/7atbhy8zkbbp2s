// Queue real EventSystem gestures. Drag movement samples the live PointerEventData.
// EndDrag stays queued across coordinator ticks, including short touch gestures.
P listenerMethod(Runtime &r, P event) {
    for (P c=r.object_get_class(event); c; c=r.class_get_parent(c)) {
        P iter=nullptr;
        while (P method=r.class_get_methods(c,&iter)) {
            if (!strcmp(r.method_get_name(method),"AddListener") && r.method_get_param_count(method)==1)
                return method;
        }
    }
    throw std::runtime_error("Map EventTrigger lacks AddListener");
}
Handle queue(Map &m) {
    P obj=m.r.object_new(m.r.type("System.Collections","Queue"));
    Handle h=m.keep(obj);
    m.r.call(obj,".ctor");
    return h;
}
void bindDrag(Map &m, P go) {
    Runtime &r=m.r;
    if (!m.starts) { m.starts=queue(m); m.ends=queue(m); }
    P trigger=add(r,go,"UnityEngine.EventSystems","EventTrigger");
    P entries=r.call(trigger,"get_triggers");
    P klass=r.nested(r.object_get_class(trigger),"Entry");
    for (int kind : {13,14}) {
        P entry=r.object_new(klass);
        m.keep(entry);
        r.call(entry,".ctor");
        P field=r.field(klass,"eventID","UnityEngine.EventSystems.EventTriggerType",false);
        r.field_set_value(entry,field,&kind);
        P event=r.get<P>(entry,"callback");
        if (!event) throw std::runtime_error("Map drag callback missing");
        P addListener=listenerMethod(r,event);
        P delegateType=r.type_get_object(r.method_get_param(addListener,0));
        P receiver=m.get(kind==13?m.starts:m.ends);
        P enqueue=r.call(r.call(receiver,"GetType"),"GetMethod",{"System.String"},{r.string_new("Enqueue")});
        // CLR relaxed delegate binding allows BaseEventData -> System.Object.
        P listener=r.stat(r.type("System","Delegate"),"CreateDelegate",
            {"System.Type","System.Object","System.Reflection.MethodInfo"},{delegateType,receiver,enqueue});
        r.invokeOn(addListener,event,{listener});
        r.call(entries,"Add",{"UnityEngine.EventSystems.EventTrigger.Entry"},{entry});
    }
}
layout::Anchors bounds(const Map &m, int index) {
    if (index<0) return puzzle::unit;
    auto &item=m.items[index];
    int parent = item.placed ? m.items[item.drop].parent : item.parent;
    if (index == m.drag) parent = -1;
    auto local = layout::lifted(item.slot, item.pose.lift);
    if (item.pose.scale == 1) return puzzle::compose(bounds(m,parent), local);
    auto size = puzzle::size(local);
    return puzzle::compose(bounds(m,parent), puzzle::centered(puzzle::center(local),
                           {size.x * item.pose.scale, size.y * item.pose.scale}));
}
void attach(Map &m, Item &item, int parent, layout::Anchors rect) {
    P tr=m.get(item.rect);
    bool world=false;
    m.r.call(tr,"SetParent",{"UnityEngine.Transform","System.Boolean"},
             {m.get(parent<0?m.rootRect:m.items[parent].rect),&world});
    setSlot(m,item,rect);
    m.r.call(tr,"SetAsLastSibling");
}
struct DragRect { float x,y,w,h; };
// Numeric pieces retain their complete authored transform chain in a root drag
// layer. Mirrored TRS ancestors preserve shear/flips without source-parent masks
// clipping the gesture. One chain is allocated during build, not per tick.
int visualParent(const Map &m, int index) {
    const auto &item=m.items[index];
    if (item.affineDrag) return item.parent;
    if (index==m.drag) return -1;
    return item.placed ? m.items[item.drop].parent : item.parent;
}
rendering::DragFrame affineFrame(const Map &m, int index, Point rootSize) {
    if (index<0) return {{},rootSize.x,rootSize.y};
    const auto &item=m.items[index];
    auto parent=affineFrame(m,visualParent(m,index),rootSize);
    return rendering::dragFrame(parent,item.slot,
        item.numericNode ? item.numericScale.x : item.pose.scale,
        item.numericNode ? item.numericScale.y : item.pose.scale,
        item.numericNode ? item.numericRotation : 0,item.pose.lift);
}
void affineSlot(Map &m, Item &item, layout::Anchors slot) {
    auto before=layout::lifted(item.slot,item.pose.lift), after=layout::lifted(slot,item.pose.lift);
    if (before.low.x!=after.low.x || before.low.y!=after.low.y)
        m.r.call(m.get(item.rect),"set_anchorMin",{"UnityEngine.Vector2"},{&after.low});
    if (before.high.x!=after.high.x || before.high.y!=after.high.y)
        m.r.call(m.get(item.rect),"set_anchorMax",{"UnityEngine.Vector2"},{&after.high});
    item.slot=slot;
}
void buildDragLayer(Map &m, Item &item) {
    item.dragLayer=std::make_unique<DragLayer>();
    auto &layer=*item.dragLayer;
    Object root=child(m,m.get(m.rootRect),"Numeric drag layer");
    layer.object=root.go; layer.rect=layer.parent=root.rect;
    stretch(m.r,m.get(root.rect));
    layer.group=m.keep(add(m.r,m.get(root.go),"UnityEngine","CanvasGroup"));
    flag(m.r,m.get(root.go),"SetActive",false);
    std::vector<int> chain;
    for (int i=item.parent;i>=0;i=m.items[i].parent) chain.push_back(i);
    layer.ancestors.reserve(chain.size());
    for (auto i=chain.rbegin();i!=chain.rend();++i) {
        Object mirror=child(m,m.get(layer.parent),"Authored drag transform");
        auto anchors=layout::lifted(m.items[*i].slot,m.items[*i].pose.lift);
        stretch(m.r,m.get(mirror.rect),anchors);
        layer.ancestors.push_back({*i,mirror.rect,anchors});
        layer.parent=mirror.rect;
    }
}
void syncDragLayers(Map &m) {
    for (auto &item:m.items) {
        if (!item.dragLayer || !item.dragLayer->attached) continue;
        auto &layer=*item.dragLayer;
        for (auto &mirror:layer.ancestors) {
            const auto &source=m.items[mirror.node];
            auto a=layout::lifted(source.slot,source.pose.lift);
            if (mirror.anchors.low.x!=a.low.x || mirror.anchors.low.y!=a.low.y)
                m.r.call(m.get(mirror.rect),"set_anchorMin",{"UnityEngine.Vector2"},{&a.low});
            if (mirror.anchors.high.x!=a.high.x || mirror.anchors.high.y!=a.high.y)
                m.r.call(m.get(mirror.rect),"set_anchorMax",{"UnityEngine.Vector2"},{&a.high});
            mirror.anchors=a;
            auto scale=source.numericNode ? source.numericScale : rendering::Transform{source.pose.scale,source.pose.scale,1};
            if (scale.x!=mirror.scale.x || scale.y!=mirror.scale.y)
                m.r.call(m.get(mirror.rect),"set_localScale",{"UnityEngine.Vector3"},{&scale});
            mirror.scale=scale;
            float rotation=source.numericNode ? source.numericRotation : 0;
            if (rotation!=mirror.rotation) {
                float euler[]={0,0,rotation};
                m.r.call(m.get(mirror.rect),"set_localEulerAngles",{"UnityEngine.Vector3"},{euler});
                mirror.rotation=rotation;
            }
        }
        float alpha=item.parent<0 ? 1 : m.items[item.parent].inheritedAlpha;
        if (alpha!=layer.alpha) {
            m.r.call(m.get(layer.group),"set_alpha",{"System.Single"},{&alpha});
            layer.alpha=alpha;
        }
    }
}
void showDragLayer(Map &m, Item &item) {
    auto &layer=*item.dragLayer;
    if (!layer.attached) {
        flag(m.r,m.get(layer.object),"SetActive",true);
        bool world=false;
        m.r.call(m.get(item.rect),"SetParent",{"UnityEngine.Transform","System.Boolean"},{m.get(layer.parent),&world});
        layer.attached=true; ++m.affineMirrors;
    }
    syncDragLayers(m);
    m.r.call(m.get(layer.rect),"SetAsLastSibling");
}
void hideDragLayer(Map &m, Item &item) {
    auto &layer=*item.dragLayer;
    if (!layer.attached) return;
    bool world=false;
    m.r.call(m.get(item.rect),"SetParent",{"UnityEngine.Transform","System.Boolean"},
        {m.get(item.parent<0?m.rootRect:m.items[item.parent].rect),&world});
    flag(m.r,m.get(layer.object),"SetActive",false);
    layer.attached=false; --m.affineMirrors;
}
bool moveAffine(Map &m, int index, rendering::DragPoint center, Point rootSize) {
    auto &item=m.items[index];
    layout::Anchors slot;
    if (!rendering::placeCenter(affineFrame(m,item.parent,rootSize),center,
                               puzzle::size(item.home),item.pose.lift,slot)) return false;
    affineSlot(m,item,slot);
    return true;
}
bool placeAffine(Map &m, int index, Point rootSize) {
    auto target=affineFrame(m,m.items[index].drop,rootSize);
    auto center=rendering::project(target.matrix,{.5,.5});
    rendering::DragPoint local;
    // A collapsed target must not become an apparently successful placement.
    return rendering::unproject(target.matrix,center,local) && moveAffine(m,index,center,rootSize);
}
void refreshAffinePlacements(Map &m) {
    bool any=false;
    DragRect area=m.r.unbox<DragRect>(m.r.call(m.get(m.rootRect),"get_rect"));
    if (!(area.w>0 && area.h>0)) return;
    for (size_t i=0;i<m.items.size();++i) {
        auto &item=m.items[i];
        if (!item.affineDrag || !item.placed) continue;
        any=true;
        if (!item.active || m.drag==int(i)) continue;
        if (!placeAffine(m,int(i),{area.w,area.h})) {
            // Singular ancestor/zero-size target: restore the authored home,
            // never divide by zero or dispatch an activation for a failed snap.
            item.placed=false;
            affineSlot(m,item,item.home);
            hideDragLayer(m,item);
        }
    }
    m.affinePlacements=any;
}
bool finishDrag(Map &m, bool place) {
    if (m.drag<0) return false;
    auto &item=m.items[m.drag];
    if (item.affineDrag) {
        DragRect area=m.r.unbox<DragRect>(m.r.call(m.get(m.rootRect),"get_rect"));
        if (place) place=placeAffine(m,m.drag,{area.w,area.h});
        if (place) { item.placed=true; m.affinePlacements=true; }
        else {
            if (item.placed && !placeAffine(m,m.drag,{area.w,area.h})) item.placed=false;
            if (!item.placed) { affineSlot(m,item,item.home); hideDragLayer(m,item); }
        }
    } else {
        if (place) {
            auto dest = puzzle::centered(puzzle::center(bounds(m,item.drop)),puzzle::size(item.authored));
            item.placedBounds = puzzle::relative(bounds(m,m.items[item.drop].parent),dest);
            item.placed=true;
        }
        int parent=item.placed?m.items[item.drop].parent:item.parent;
        attach(m,item,parent,item.placed?item.placedBounds:item.home);
    }
    if (!place && item.originalSibling>=0)
        m.r.call(m.get(item.rect),"SetSiblingIndex",{"System.Int32"},{&item.originalSibling});
    m.r.gchandle_free(m.pointer); m.pointer=0; m.drag=-1;
    return place;
}
void cancelDrag(Map &m) {
    finishDrag(m,false);
    if (!m.starts) return;
    for (Handle h : {m.starts,m.ends}) {
        P events=m.get(h);
        for (int n=m.r.count(events); n>0; --n) m.r.call(events,"Dequeue");
    }
}
P rayHit(Runtime &r, P event, const char *raycast) {
    P box=r.call(event,raycast);
    return r.get<P>(box,"m_GameObject");
}
bool scenePoint(Map &m, P event, const char *property, DragRect area, Point &point) {
    Runtime &r=m.r;
    Point screen=r.unbox<Point>(r.call(event,property));
    P camera=r.call(event,"get_pressEventCamera");
    Point local{};
    bool ok=r.unbox<bool>(r.stat(r.type("UnityEngine","RectTransformUtility"),"ScreenPointToLocalPointInRectangle",
        {"UnityEngine.RectTransform","UnityEngine.Vector2","UnityEngine.Camera","UnityEngine.Vector2&"},
        {m.get(m.rootRect),&screen,camera,&local}));
    if (!ok || area.w<=0 || area.h<=0) return false;
    point={(local.x-area.x)/area.w,(local.y-area.y)/area.h};
    return true;
}
bool eligible(const Map &m, int i) {
    return m.items[i].active && m.items[i].inheritedAlpha>.01f;
}
bool atTarget(const Map &m, int i, Point p) {
    for (;i>=0;i=m.items[i].parent)
        if (!eligible(m,i) || !puzzle::contains(bounds(m,i),p)) return false;
    return puzzle::contains(puzzle::unit,p);
}
bool atAffineTarget(const Map &m, int index, rendering::DragPoint p, Point rootSize) {
    if (!(p.x>=0 && p.x<1 && p.y>=0 && p.y<1)) return false;
    for (int i=index;i>=0;i=visualParent(m,i))
        if (!eligible(m,i) || !rendering::contains(affineFrame(m,i,rootSize),p)) return false;
    return true;
}
int puzzleInput(Map &m) {
    if (!m.starts || !m.input) return -1;
    Runtime &r=m.r;
    P starts=m.get(m.starts), ends=m.get(m.ends);
    int startCount=r.count(starts), endCount=r.count(ends);
    if (!startCount && !endCount && m.drag<0) return -1;
    DragRect area=r.unbox<DragRect>(r.call(m.get(m.rootRect),"get_rect"));
    for (int j=0;j<startCount;++j) {
        P e=r.call(starts,"Dequeue");
        if (m.drag>=0 || r.enumValue(r.call(e,"get_button"),"UnityEngine.EventSystems.PointerEventData.InputButton")!=0) continue;
        P hit=rayHit(r,e,"get_pointerPressRaycast");
        if (!hit) continue;
        for (size_t i=0;i<m.items.size();++i) {
            Item &item=m.items[i];
            if (!item.hitObject || hit!=m.get(item.hitObject) || !eligible(m,int(i))) continue;
            Point down;
            if (!scenePoint(m,e,"get_pressPosition",area,down)) break;
            if (item.affineDrag) {
                auto frame=affineFrame(m,int(i),{area.w,area.h});
                if (!rendering::unproject(frame.matrix,{down.x,down.y},m.affineGrab)) break;
                item.originalSibling=r.unbox<int>(r.call(m.get(item.rect),"GetSiblingIndex"));
                m.pointer=r.gchandle_new(e,false);
                if (!m.pointer) throw std::runtime_error("Map pointer handle failed");
                m.drag=int(i); m.dragSize={area.w,area.h};
                showDragLayer(m,item);
                break;
            }
            auto visibleBounds = bounds(m,int(i));
            Point center=puzzle::center(visibleBounds);
            m.grab={center.x-down.x,center.y-down.y};
            item.originalSibling=r.unbox<int>(r.call(m.get(item.rect),"GetSiblingIndex"));
            m.pointer=r.gchandle_new(e,false);
            if (!m.pointer) throw std::runtime_error("Map pointer handle failed");
            m.drag=int(i); m.dragSize={area.w,area.h};
            m.pieceSize = puzzle::size(visibleBounds);
            applyPose(m,item,{});
            attach(m,item,-1,visibleBounds);
            break;
        }
    }
    bool ended=false;
    for (int j=0;j<endCount;++j) if (r.call(ends,"Dequeue")==m.get(m.pointer)) ended=true;
    if (m.drag<0) return -1;
    int index=m.drag;
    Item &item=m.items[index];
    P event=m.get(m.pointer);
    Point p;
    if ((!ended && !r.call(event,"get_pointerDrag")) || !eligible(m,index) || area.w!=m.dragSize.x || area.h!=m.dragSize.y || !scenePoint(m,event,"get_position",area,p)) {
        finishDrag(m,false); return -1;
    }
    if (item.affineDrag) {
        rendering::DragPoint center;
        if (!rendering::dragCenter(affineFrame(m,index,{area.w,area.h}),m.affineGrab,{p.x,p.y},center)) {
            finishDrag(m,false); return -1;
        }
        if (ended) {
            bool accepted=rayHit(r,event,"get_pointerCurrentRaycast") &&
                atAffineTarget(m,item.drop,center,{area.w,area.h});
            accepted=finishDrag(m,accepted);
            return accepted ? index : -1;
        }
        if (!moveAffine(m,index,center,{area.w,area.h})) finishDrag(m,false);
        return -1;
    }
    p.x+=m.grab.x; p.y+=m.grab.y;
    if (ended) {
        // The mobile input module clears pointerCurrentRaycast for cancelled touches.
        // A transparent map backing supplies a valid raycast even over empty frames.
        bool accepted=rayHit(r,event,"get_pointerCurrentRaycast") && atTarget(m,item.drop,p);
        finishDrag(m,accepted);
        return accepted ? index : -1;
    }
    setSlot(m,item,puzzle::centered(p,m.pieceSize));
    return -1;
}
