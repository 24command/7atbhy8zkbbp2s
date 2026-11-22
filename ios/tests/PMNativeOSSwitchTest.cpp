#include "../PhiMod/Sources/PMNativeOSSwitch.hpp"
#include <cassert>
#include <initializer_list>

int main() {
    using namespace pmnativeswitch;
    for (Face face : {Face::Hidden, Face::List, Face::OS}) {
        for (bool owned : {false, true}) for (bool input : {false, true}) {
            for (bool unityAllows : {false, true}) {
                int checks = 0;
                Press result = detail::routePress(owned, face, input, [&] { ++checks; return unityAllows; });
                assert(checks == int(owned && input && face != Face::Hidden));
                if (!owned) assert(result == Press::Pass);
                else if (!input || !unityAllows || face == Face::Hidden) assert(result == Press::Consumed);
                else if (face == Face::List) assert(result == Press::OpenOS);
                else assert(result == Press::OpenList);
            }
        }
    }
}
