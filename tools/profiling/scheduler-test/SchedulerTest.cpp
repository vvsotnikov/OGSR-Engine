#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>
#define ENGINE_API
#define VERIFY(...)
#define R_ASSERT(...)
#define ZoneScoped
#define ZoneScopedN(...)
#define TRUE 1
#define FALSE 0
using u32 = uint32_t;
using BOOL = bool;
template<class T> using xr_vector = std::vector<T>;
struct shared_str : std::string { using std::string::string; const char* operator*() const { return c_str(); } };
template<class T> void clamp(T& value, T low, T high) { value = std::clamp(value, low, high); }
int iFloor(float value) { return int(std::floor(value)); }
template<class... Args> void Msg(Args...) {}
uint64_t clock_ms = 0;
struct CTimer { uint64_t start; void Start() { start = clock_ms; } u32 GetElapsed_ms() const { return u32(clock_ms-start); } };
struct Stat { struct { void Begin() {} void End() {} } Sheduler; float fShedulerLoad; } statistics;
struct { u32 dwTimeGlobal=0, dwPrecacheFrame=0; Stat* Statistic=&statistics; } Device;
struct ISheduled {
    struct { u32 t_min=100, t_max=250; bool b_RT=false, b_locked=false; } shedule;
    virtual ~ISheduled() = default;
    virtual float shedule_Scale() = 0;
    virtual void shedule_Update(u32) = 0;
    virtual shared_str shedule_Name() const { return "fixture"; }
    virtual bool shedule_Needed() = 0;
};
#define private public
#include "scheduler-under-test.h"
#undef private
#include "scheduler-under-test.cpp"

uint64_t digest=1469598103934665603ull;
void record(uint64_t value) { digest=(digest^value)*1099511628211ull; }
struct NPC;
CSheduler* scheduler;
std::vector<NPC>* population;
u32 frame=0, calls=0, needed=0, self_removals=0, other_removals=0, registrations=0;
struct NPC : ISheduled {
    u32 id, salt, updates=0;
    bool registered=true;
    NPC(u32 number, u32 seed) : id(number), salt(seed) {}
    float shedule_Scale() override { return float((id*17+salt)%200)/100.f; }
    bool shedule_Needed() override {
        ++needed; record(1); record(id);
        if ((id+salt)%31==0 && frame>3) { registered=false; return false; }
        return true;
    }
    void shedule_Update(u32 dt) override {
        ++calls; ++updates; record(2); record(id); record(dt);
        clock_ms+=(id+salt+updates)%4;
        if (shedule.b_RT) return;
        if ((id+updates+salt)%19==0) {
            scheduler->Unregister(this, true); registered=false; ++self_removals;
            if (updates%2==0) { scheduler->Register(this); registered=true; ++registrations; }
        }
        auto& other=population->at((id*7+salt+updates)%population->size());
        if (&other!=this && other.registered && (id+updates)%5==0) {
            scheduler->Unregister(&other, true); other.registered=false; ++other_removals;
        }
    }
};
int main() {
    for(u32 seed=0; seed<200; ++seed) {
        CSheduler instance; scheduler=&instance; instance.Initialize();
        std::vector<NPC> npcs; population=&npcs; npcs.reserve(96);
        psShedulerCurrent=10; psShedulerTarget=10; clock_ms=0;
        for(u32 i=0;i<96;++i) { npcs.emplace_back(i,seed); }
        Device.dwTimeGlobal=0;
        for(auto& npc:npcs) instance.Register(&npc);
        for(frame=0;frame<100;++frame) {
            Device.dwTimeGlobal+=17+(frame*13+seed)%31;
            Device.dwPrecacheFrame=frame<4 ? 1 : 0;
            // Include external forced unregister, deferred registration and RT work.
            if(frame==8) { auto& npc=npcs[95]; if(npc.registered) instance.Unregister(&npc,true); instance.Register(&npc,true); npc.registered=true; }
            // RT mutations are excluded: their vector invalidation is a separate existing issue.
            if(frame==9) { instance.Unregister(&npcs[95],true); npcs[95].registered=false; }
            instance.Update();
            record(frame); record(u32(psShedulerCurrent*10000));
            for(auto& item:instance.Items) if(item.Object) {
                record(static_cast<NPC*>(item.Object)->id); record(item.dwTimeForExecute); record(item.dwTimeOfLastExecute);
            }
        }
        instance.Destroy();
    }
    std::cout<<digest<<" "<<calls<<" "<<needed<<" "<<self_removals<<" "<<other_removals<<" "<<registrations<<"\n";
}
