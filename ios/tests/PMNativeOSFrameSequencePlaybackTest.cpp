#include "../PhiMod/Sources/PMNativeOSFrameSequencePlayback.hpp"
#include <cassert>
#include <cmath>
#include <iostream>
#include <limits>
using P=pmpma::Playback;
using A=P::Action;
static void display(P &p,std::size_t i,double now) {
    auto token=p.request(i,now);assert(token);assert(p.owns(token,i));assert(p.display(token,i,now));
}
static void preparation() {
    P p(10);auto t=p.request(0,10);assert(t && !p.canSkip());
    assert(p.poll(29.9)==A::Wait);assert(p.configure(3,.1,0));
    assert(p.display(t,0,29.9));assert(p.elapsed(29.9)==0);assert(p.canSkip());
    assert(p.poll(29.95)==A::Wait);assert(p.poll(30.01)==A::Decode);
    P never(0);never.request(0,0);assert(never.poll(20.01)==A::Fail);
}
static void naturalEnd() {
    P p;assert(p.configure(3,.1,0));display(p,0,0);
    assert(p.poll(.11)==A::Decode);display(p,1,.11);
    assert(p.poll(.21)==A::Decode);display(p,2,.21);
    assert(p.poll(.305)==A::Wait);assert(p.poll(.311)==A::Complete);
    p.cancel();assert(p.poll(100)==A::Wait);assert(!p.canSkip());
}
static void singleAndLimits() {
    P p;assert(p.configure(1,.5,0));display(p,0,1);
    assert(p.poll(1.49)==A::Wait);assert(p.poll(1.51)==A::Complete);
    P q;assert(q.configure(20,.1,.25));assert(q.terminal()==2);display(q,0,0);display(q,2,.2);
    assert(q.poll(.249)==A::Wait);assert(q.poll(.251)==A::Complete);assert(q.elapsed(50)==.25);
    P exact;assert(exact.configure(20,.1,.2));assert(exact.terminal()==1);
    P subframe;assert(subframe.configure(2,.1,.025));assert(subframe.terminal()==0);display(subframe,0,0);
    assert(subframe.poll(.026)==A::Complete);
    P longFrame;assert(longFrame.configure(1,600.,0));display(longFrame,0,0);
    assert(longFrame.poll(599)==A::Wait);assert(longFrame.poll(600)==A::Complete);
    assert(longFrame.poll(611)==A::Fail);
}
static void lateTerminalCannotFinishEarly() {
    P p;assert(p.configure(4,.1,0));display(p,0,0);
    assert(p.poll(3)==A::Decode && p.target(3)==3);
    auto token=p.request(3,3);assert(token);assert(!p.request(3,3));
    assert(p.poll(4)==A::Wait);assert(p.display(token,3,4));
    assert(p.poll(4.05)==A::Wait);assert(p.poll(4.101)==A::Complete);
}
static void cancellationAndOwnership() {
    P p;auto t=p.request(0,0);assert(t);p.cancel();assert(!p.owns(t,0));
    assert(!p.configure(1,.1,0));assert(!p.display(t,0,0));assert(!p.request(0,1));
    P active;assert(active.configure(3,.1,0));display(active,0,0);
    t=active.request(1,.11);assert(!active.owns(t,2));assert(!active.owns(t+1,1));
    assert(active.display(t,1,.12));assert(!active.display(t,1,.12));
    auto next=active.request(2,.21);assert(next!=t);assert(!active.owns(t,1));
    active.cancel();assert(!active.owns(next,2));
    P background;assert(background.poll(0,false)==A::Fail);
}
static void errorsAndBudgets() {
    P p;assert(!p.configure(0,.1,0));assert(!p.configure(4097,.1,0));
    assert(!p.configure(1,1./61.,0));assert(!p.configure(2,400,0));
    assert(!p.configure(1,.1,-1));assert(!p.configure(1,.1,std::numeric_limits<double>::infinity()));
    assert(!p.configure(1,std::numeric_limits<double>::quiet_NaN(),0));
    assert(p.configure(4096,1./60.,0));assert(p.count==4096);
    display(p,0,0);auto t=p.request(1,1./60.);assert(t);assert(p.poll(21)==A::Fail);
    assert(!p.request(4096,22));assert(!p.setLimit(-1));
    assert(p.poll(std::numeric_limits<double>::quiet_NaN())==A::Fail);
}
int main(){preparation();naturalEnd();singleAndLimits();lateTerminalCannotFinishEarly();cancellationAndOwnership();errorsAndBudgets();
 std::cout<<"PMA one-shot: 6 behavioral groups passed\n";
}
