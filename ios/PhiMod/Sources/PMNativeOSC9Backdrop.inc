// The level30 NoiseBg Image carries the MapRedToAllChannel material. Leave its
// animated world hierarchy dormant and share only the stock drawing assets.
P mountPhaseTwoBackdrop(Chrome &c) {
    Runtime &r = c.r;
    P source = component(r,find(r,c.host,"UI/WorldCanvas/Background/NoiseBg"),ui,"Image");
    P sprite = r.call(source,"get_sprite"), material = r.call(source,"get_material");
    require(r.alive(sprite) && r.alive(material),"Chrome: missing C9 phase two backdrop assets");
    P object = container(c,c.map,"PMPhaseTwoBackdrop",true);
    P image = add(r,object,ui,"Image");
    r.call(image,"set_sprite",{"UnityEngine.Sprite"},{sprite});
    r.call(image,"set_material",{"UnityEngine.Material"},{material});
    struct Color { float red, green, blue, alpha; };
    Color tint = r.unbox<Color>(r.call(source,"get_color"));
    r.call(image,"set_color",{"UnityEngine.Color"},{&tint});
    flag(r,image,"set_raycastTarget",false);
    return object; // Created inactive. Chrome reveals it only on the map face.
}
