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
void finishDrag(Map &m, bool place) {
    if (m.drag<0) return;
    auto &item=m.items[m.drag];
    if (place) {
        auto dest = puzzle::centered(puzzle::center(bounds(m,item.drop)),puzzle::size(item.authored));
        item.placedBounds = puzzle::relative(bounds(m,m.items[item.drop].parent),dest);
        item.placed=true;
    }
    int parent=item.placed?m.items[item.drop].parent:item.parent;
    attach(m,item,parent,item.placed?item.placedBounds:item.home);
    if (!place && item.originalSibling>=0)
        m.r.call(m.get(item.rect),"SetSiblingIndex",{"System.Int32"},{&item.originalSibling});
    m.r.gchandle_free(m.pointer); m.pointer=0; m.drag=-1;
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
struct DragRect { float x,y,w,h; };
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
