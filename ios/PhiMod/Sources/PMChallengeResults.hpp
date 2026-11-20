#pragma once
// Include inside PMHookBackend's anonymous namespace after pmchallenge.
// Scene level9 (4.0.3): Start is synchronous. Back(bool) can persist rank.
namespace pmchallengeresults {
struct View {
    uint32_t owner = 0;
    P previous = nullptr, next = nullptr, caption = nullptr;
    int page = 0, pages = 1;
    long long total = 0;
    bool leaving = false;
};
static View view;

void clear(Runtime &r) {
    if (view.owner) r.gchandle_free(view.owner);
    view = {};
}
P gameObject(Runtime &r, P component) { return r.call(component, "get_gameObject"); }
void active(Runtime &r, P object, bool visible) {
    if (object) r.call(object, "SetActive", {"System.Boolean"}, {&visible});
}
P child(Runtime &r, P parent, const char *name) {
    P tr = r.call(parent, "Find", {"System.String"}, {r.string_new(name)});
    if (!tr) throw std::runtime_error(std::string("Missing result child ") + name);
    return gameObject(r, tr);
}
void afterStart(Runtime &r, P self) {
    try {
        if (!pmchallenge::hpVisible(r)) return;
        active(r, r.get<P>(self, "secretChallengeResultComponent"), true);
        char text[96];
        P damageText = r.get<P>(self, "damageNumText");
        snprintf(text, sizeof(text), "%g", double(pmchallenge::damage));
        r.text(damageText, text);
        // Stock LIFE badges bake a fixed number into their sprite. A custom HP
        // maximum can be arbitrary, so draw its actual value at the badge anchor.
        P badge = r.get<P>(self, "lifeImage"), parent = r.call(badge, "get_transform");
        bool disabled = false;
        P sprites = r.get<P>(self, "lifeSprites");
        P rules = r.type("Phigros2.ChallengeMode.Scripts", "SecretChallengeLifeRules");
        for (int tier = 0; sprites && uintptr_t(tier) < r.array_length(sprites); ++tier) {
            int value = r.unbox<int>(r.stat(rules, "GetLifeForTierIndex", {"System.Int32"}, {&tier}));
            P sprite = r.arrayAt(sprites, tier);
            if (sprite && pmchallenge::initialLife == value) {
                r.call(badge, "set_sprite", {"UnityEngine.Sprite"}, {sprite});
                return;
            }
        }
        r.call(badge, "set_enabled", {"System.Boolean"}, {&disabled});
        P hp = r.stat(r.type("UnityEngine", "Object"), "Instantiate", {"UnityEngine.Object", "UnityEngine.Transform", "System.Boolean"}, {damageText, parent, &disabled});
        P rect = r.call(hp, "get_rectTransform");
        V2 zero{0,0}, full{1,1};
        r.call(rect,"set_anchorMin",{"UnityEngine.Vector2"},{&zero});
        r.call(rect,"set_anchorMax",{"UnityEngine.Vector2"},{&full});
        r.call(rect,"set_offsetMin",{"UnityEngine.Vector2"},{&zero});
        r.call(rect,"set_offsetMax",{"UnityEngine.Vector2"},{&zero});
        int center = 4; bool fit = true;
        r.call(hp,"set_alignment",{"UnityEngine.TextAnchor"},{&center});
        r.call(hp,"set_resizeTextForBestFit",{"System.Boolean"},{&fit});
        snprintf(text, sizeof(text), "%g\nLIFE", double(pmchallenge::initialLife));
        r.text(hp,text);
    } catch (const std::exception &e) { diagf("Challenge HP result: %s", e.what()); }
}

// Create new Text/Button components. These have no serialized rank/retry listeners.
P add(Runtime &r, P go, const char *ns, const char *name) {
    return r.call(go, "AddComponent", {"System.Type"}, {r.type_get_object(r.class_get_type(r.type(ns, name)))});
}
P pagerLabel(Runtime &r, P parent, P font, const char *name, float x, bool button) {
    P go = r.object_new(r.type("UnityEngine", "GameObject"));
    r.call(go, ".ctor", {"System.String"}, {r.string_new(name)});
    P rect = add(r, go, "UnityEngine", "RectTransform");
    bool no = false;
    r.call(rect, "SetParent", {"UnityEngine.Transform", "System.Boolean"}, {parent, &no});
    int layer = r.unbox<int>(r.call(gameObject(r, parent), "get_layer"));
    r.call(go, "set_layer", {"System.Int32"}, {&layer});
    V2 anchor{0.47f, 1}, size{button ? 80.f : 200.f, 80}, pos{x, -62};
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

void showCard(Runtime &r, P card, P item) {
    P selector = item ? r.get<P>(item, "songInfo") : nullptr;
    P song = selector ? r.get<P>(selector, "songInfo") : nullptr;
    P result = item ? r.get<P>(item, "result") : nullptr;
    int slot = item ? r.get<int>(item, "levelIndex") : -1;
    auto label = [&](const char *field, const char *value) { r.text(r.get<P>(card, field), value); };
    label("songsName", song ? r.string(r.get<P>(song, "songsName")).UTF8String : "—");
    P levels = song ? r.get<P>(song, "levels") : nullptr;
    label("songsLevel", levels && slot >= 0 && uintptr_t(slot) < r.array_length(levels)
          ? r.string(r.arrayAt(levels, slot)).UTF8String : "");
    P difficulty = song ? r.get<P>(song, "difficulty") : nullptr;
    char buffer[48] = {};
    if (difficulty && slot >= 0 && uintptr_t(slot) < r.array_length(difficulty))
        snprintf(buffer, sizeof(buffer), "%.1f", double(r.unbox<float>(r.arrayAt(difficulty, slot))));
    label("songsDifficulty", buffer);
    if (NSDictionary *chart = pmcontent::challengeEntryChart(r, item)) {
        label("songsLevel", PMDifficultyName(chart[@"level"]).UTF8String);
        label("songsDifficulty", PMDifficultyText(chart).UTF8String);
    }
    snprintf(buffer, sizeof(buffer), "%07d", result ? r.get<int>(result,"<IntScore>k__BackingField") : 0);
    label("scoreText", result ? buffer : "—");
    for (auto stat : {"perfect", "good", "bad", "miss", "early", "late"}) {
        auto field = std::string(stat) + "Text";
        label(field.c_str(), result ? std::to_string(r.get<int>(result, stat)).c_str() : "—");
    }
    P cover = r.get<P>(card, "cover");
    P key = selector ? r.get<P>(selector, "coverAssetCode") : nullptr;
    try { r.call(cover, "set_Code", {"System.String"}, {key ? key : r.string_new("")}); }
    catch (const std::exception &e) { diagf("Challenge result cover: %s", e.what()); }
}
P canvas(Runtime &r, P self) {
    return r.call(r.call(r.get<P>(self,"retryButton"),"get_transform"),"get_parent");
}
void show(Runtime &r, P self) {
    P list = pmchallenge::list(r), cards = r.get<P>(self, "levelOverComponents"), root = canvas(r,self);
    const char *rows[] = {"SettleAccount", "SettleAccount (1)", "SettleAccount (2)"};
    int count = r.count(list);
    for (int i = 0; i < 3; ++i) {
        int index = view.page * 3 + i;
        active(r, child(r, root, rows[i]), index < count);
        if (index < count) showCard(r, r.at(cards, i), r.at(list, index));
    }
    char text[80];
    snprintf(text, sizeof(text), "%d / %d", view.page + 1, view.pages);
    r.text(view.caption, text);
    bool canPrev = view.page > 0, canNext = view.page + 1 < view.pages;
    auto updateArrow = [&](P button,bool enabled) {
        Color background = enabled ? Color{.08f,.09f,.11f,.95f} : Color{.32f,.32f,.32f,.8f};
        r.call(r.call(button,"get_targetGraphic"),"set_color",{"UnityEngine.Color"},{&background});
        r.call(button,"set_interactable",{"System.Boolean"},{&enabled});
    };
    updateArrow(view.previous,canPrev);
    updateArrow(view.next,canNext);
}

bool start(Runtime &r, P self) {
    clear(r);
    if (!pmchallenge::variable()) return false;
    view.owner = r.gchandle_new(self, false);
    try {
        P root = canvas(r,self), score = r.get<P>(self, "score"), font = r.call(score, "get_font");
        active(r, gameObject(r, r.get<P>(self, "retryButton")), false);
        active(r, gameObject(r, r.get<P>(self, "selectRankWindow")), false);
        active(r, r.get<P>(self, "normal3rdComponent"), true);
        active(r, r.get<P>(self, "secretComponent"), false);
        P ratings = r.get<P>(self, "ratings");
        for (uintptr_t i = 0; ratings && i < r.array_length(ratings); ++i) active(r, r.arrayAt(ratings, int(i)), false);
        P list = pmchallenge::list(r);
        int count = r.count(list);
        view.pages = count > 0 ? 1 + (count - 1) / 3 : 1;
        for (int i = 0; i < count; ++i) {
            P entry = r.at(list, i), result = entry ? r.get<P>(entry,"result") : nullptr;
            if (result) view.total += r.get<int>(result,"<IntScore>k__BackingField");
        }
        r.text(score, std::to_string(view.total).c_str());
        view.caption = pagerLabel(r, root, font, "PhiMod Result Page", 0, false);
        view.previous = pagerLabel(r, root, font, "←", -130, true);
        view.next = pagerLabel(r, root, font, "→", 130, true);
        show(r, self);
    } catch (const std::exception &e) { diagf("Variable challenge result: %s", e.what()); }
    afterStart(r,self);
    return true; // Even partial presentation must consume Start.
}

// level9 serializes OpenRankWindow, Back(bool) and Retry into four buttons.
// Match the verified scene hierarchy. Persistent-event inspection APIs are stripped.
enum class Action { Pass, Previous, Next, Leave, Block };
Action action(Runtime &r, P button, P self) {
    if (button == view.previous) return Action::Previous;
    if (button == view.next) return Action::Next;
    P retry = r.get<P>(self,"retryButton");
    if (button == retry) return Action::Block;
    P tr = r.call(button,"get_transform"), parent = r.call(tr,"get_parent");
    if (parent == canvas(r,self) && [r.string(r.call(button,"get_name")) isEqualToString:@"Back"])
        return Action::Leave;
    if (parent == r.call(r.get<P>(self,"selectRankWindow"),"get_transform")) return Action::Block;
    return Action::Pass;
}
bool route(Runtime &r, P button, P pointer, bool isPointer) {
    if (!view.owner) return false;
    try {
        P self = r.gchandle_get_target(view.owner);
        if (!r.alive(self)) { clear(r); return false; }
        Action input = action(r,button,self);
        if (input == Action::Pass) return false;
        if (view.leaving || input == Action::Block) return true;
        if (isPointer && (!pointer || r.enumValue(r.call(pointer,"get_button"),"UnityEngine.EventSystems.PointerEventData.InputButton") != 0)) return true;
        if (!r.unbox<bool>(r.call(button,"IsActive")) || !r.unbox<bool>(r.call(button,"IsInteractable"))) return true;
        if (input == Action::Leave) {
            P transition = r.call(self,"TurnToNextScene",{"System.String"},{r.string_new("SongSelector")});
            r.call(self,"StartCoroutine",{"System.Collections.IEnumerator"},{transition});
            view.leaving = true;
        } else {
            view.page = std::max(0, std::min(view.pages - 1, view.page + (input == Action::Next ? 1 : -1)));
            show(r,self);
        }
    } catch (const std::exception &e) { diagf("Challenge result input: %s", e.what()); }
    return true;
}
bool press(Runtime &r, P button) { return route(r,button,nullptr,false); }
bool pointerClick(Runtime &r, P button, P event) { return route(r,button,event,true); }
} // namespace pmchallengeresults
