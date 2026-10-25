#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <UIKit/UIKit.h>
#import "imgui.h"
#import "imgui_internal.h"
#import "backends/imgui_impl_metal.h"
#import "backends/imgui_impl_ios.h"

// External declarations for hooks and patches
extern void* getBase();
extern uintptr_t getRealOffset(uintptr_t offset);
extern void PatchMemory(uintptr_t address, uint32_t value);
extern void DobbyHook(void* symbol, void* replace, void** backup);

static bool esp_boxes = false;
static bool esp_health = false;
static bool esp_distance = false;
static bool esp_skeleton = false;

static bool aim_assist = false;
static bool aim_triggerbot = false;
static float aim_fov = 100.f;
static float aim_smooth = 5.f;

static bool move_jumphack = false;
static bool move_parachute = false;
static bool move_autoclimb = false;
static bool move_walkthrough = false;
static bool move_underwater = false;
static bool move_j_active = false;
static bool move_p_active = false;
static bool move_c_active = false;
static bool move_w_active = false;
static bool move_u_active = false;

static bool misc_antispectate = false;
static bool misc_grave = false;
static bool misc_a_active = false;
static bool misc_g_active = false;

// Offsets placeholder
#define OFS_VIEWMATRIX 0x0
#define OFS_PLAYER_X 0x0
#define OFS_PLAYER_Y 0x0
#define OFS_PLAYER_Z 0x0
#define OFS_ENTITYLIST 0x0
#define OFS_JUMPHACK 0x0
#define OFS_FASTPARACHUTE 0x0
#define OFS_AUTOCLIMB 0x0
#define OFS_WALKTHROUGH 0x0
#define OFS_UNDERWATER 0x0
#define OFS_ANTISPECTATE 0x0
#define OFS_GRAVE 0x0

struct Vector3 { float x, y, z; };
struct Vector2 { float x, y; };
struct ScreenPoint { float x, y; bool valid; };

static float readFloat(uintptr_t addr) {
    if (!addr) return 0.f;
    return *(float*)addr;
}

static bool WorldToScreen(Vector3 worldPos, Vector2 &screen, const float matrix[16], float windowWidth, float windowHeight) {
    float w = matrix[12] * worldPos.x + matrix[13] * worldPos.y + matrix[14] * worldPos.z + matrix[15];
    if (w < 0.01f) return false;
    
    float x = matrix[0] * worldPos.x + matrix[1] * worldPos.y + matrix[2] * worldPos.z + matrix[3];
    float y = matrix[4] * worldPos.x + matrix[5] * worldPos.y + matrix[6] * worldPos.z + matrix[7];
    
    float invW = 1.0f / w;
    screen.x = (windowWidth * 0.5f) + (x * invW * (windowWidth * 0.5f));
    screen.y = (windowHeight * 0.5f) - (y * invW * (windowHeight * 0.5f));
    return true;
}

@interface ImGuiDrawView : UIViewController <MTKViewDelegate>
@property (nonatomic, strong) MTKView *mtkView;
@end

@implementation ImGuiDrawView

- (void)loadView {
    self.mtkView = [[MTKView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.mtkView.device = MTLCreateSystemDefaultDevice();
    self.mtkView.delegate = self;
    self.mtkView.backgroundColor = [UIColor clearColor];
    self.mtkView.opaque = NO;
    self.view = self.mtkView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO(); (void)io;
    ImGui::StyleColorsDark();
    ImGui_ImplMetal_Init(self.mtkView.device);
}

- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {}

- (void)drawInMTKView:(MTKView*)view {
    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize = ImVec2(view.drawableSize.width, view.drawableSize.height);
    
    ImGui_ImplMetal_NewFrame(view);
    ImGui::NewFrame();
    
    ImGui::Begin("Mod Menu", nullptr, ImGuiWindowFlags_None);
    if (ImGui::BeginTabBar("Tabs"))
    {
        if (ImGui::BeginTabItem("Visuals"))
        {
            ImGui::Checkbox("Player Boxes",  &esp_boxes);
            ImGui::Checkbox("Health Bars",   &esp_health);
            ImGui::Checkbox("Distance",      &esp_distance);
            ImGui::Checkbox("Skeleton",      &esp_skeleton);
            ImGui::EndTabItem();
        }
        if (ImGui::BeginTabItem("Aim"))
        {
            ImGui::Checkbox("Aim Assist",    &aim_assist);
            ImGui::Checkbox("Triggerbot",    &aim_triggerbot);
            ImGui::SliderFloat("FOV",        &aim_fov,    10.f, 300.f);
            ImGui::SliderFloat("Smooth",     &aim_smooth,  1.f,  20.f);
            ImGui::EndTabItem();
        }
        if (ImGui::BeginTabItem("Move"))
        {
            ImGui::Checkbox("Jump Hack",         &move_jumphack);
            ImGui::Checkbox("Fast Parachute",    &move_parachute);
            ImGui::Checkbox("Auto Climb",        &move_autoclimb);
            ImGui::Checkbox("Walkthrough Walls", &move_walkthrough);
            ImGui::Checkbox("Underwater",        &move_underwater);
            ImGui::EndTabItem();
        }
        if (ImGui::BeginTabItem("Misc"))
        {
            ImGui::Checkbox("Anti-Spectate",  &misc_antispectate);
            ImGui::Checkbox("Grave",          &misc_grave);
            ImGui::EndTabItem();
        }
        ImGui::EndTabBar();
    }
    ImGui::End();
    
    ImDrawList* draw_list = ImGui::GetBackgroundDrawList();
    float sw = view.drawableSize.width;
    float sh = view.drawableSize.height;
    
    if (esp_boxes || esp_health || esp_distance || esp_skeleton)
    {
        float vm[16];
        uintptr_t vmBase = getBase() + OFS_VIEWMATRIX;
        for (int i = 0; i < 16; i++)
            vm[i] = *(float *)(vmBase + i * 4);
        float lx = readFloat(OFS_PLAYER_X);
        float ly = readFloat(OFS_PLAYER_Y);
        float lz = readFloat(OFS_PLAYER_Z);
        uintptr_t entityList = *(uintptr_t *)(getBase() + OFS_ENTITYLIST);
        if (entityList) {
            for (int i = 0; i < 100; i++) {
                uintptr_t entity = *(uintptr_t *)(entityList + i * 0x8);
                if (!entity) continue;
                float ex = *(float *)(entity + 0xDC);
                float ey = *(float *)(entity + 0xE0);
                float ez = *(float *)(entity + 0xE4);
                if (fabsf(ex) > 100000 || fabsf(ey) > 100000 || fabsf(ez) > 100000) continue;
                float dist = sqrtf(powf(ex-lx,2)+powf(ey-ly,2)+powf(ez-lz,2));
                if (dist > 800.f) continue;
                Vector3 feetPos = {ex, ey, ez};
                Vector3 headPos = {ex, ey + 1.8f, ez};
                Vector2 screenFeet, screenHead;
                if (!WorldToScreen(feetPos, screenFeet, vm, sw, sh)) continue;
                if (!WorldToScreen(headPos, screenHead, vm, sw, sh)) continue;
                float boxH = fabsf(screenFeet.y - screenHead.y);
                float boxW = boxH * 0.4f;
                if (esp_boxes) {
                    draw_list->AddRect(
                        ImVec2(screenHead.x - boxW/2, screenHead.y),
                        ImVec2(screenHead.x + boxW/2, screenFeet.y),
                        IM_COL32(255, 50, 50, 220), 0.f, 0, 2.0f);
                }
                if (esp_health) {
                    float barX = screenHead.x - boxW/2 - 6.f;
                    draw_list->AddRectFilled(
                        ImVec2(barX-3, screenHead.y),
                        ImVec2(barX,   screenFeet.y),
                        IM_COL32(50,50,50,200));
                    draw_list->AddRectFilled(
                        ImVec2(barX-3, screenFeet.y - boxH),
                        ImVec2(barX,   screenFeet.y),
                        IM_COL32(50,255,50,220));
                }
                if (esp_distance) {
                    char distStr[32];
                    snprintf(distStr, sizeof(distStr), "%.0fm", dist);
                    draw_list->AddText(
                        ImVec2(screenHead.x - 12, screenFeet.y + 2),
                        IM_COL32(255,255,255,220), distStr);
                }
                if (esp_skeleton) {
                    draw_list->AddLine(
                        ImVec2(screenHead.x, screenHead.y),
                        ImVec2(screenFeet.x, screenFeet.y),
                        IM_COL32(255,200,0,180), 1.5f);
                }
            }
        }
    }
    
    if (aim_assist) {
        draw_list->AddCircle(
            ImVec2(sw/2, sh/2), aim_fov,
            IM_COL32(255,255,255,120), 64, 1.5f);
    }
    
    if (move_jumphack) {
        if (!move_j_active) { PatchMemory(OFS_JUMPHACK, 0x360080D2); move_j_active = true; }
    } else if (move_j_active) { PatchMemory(OFS_JUMPHACK, 0xF60302AA); move_j_active = false; }
    
    if (move_parachute) {
        if (!move_p_active) { PatchMemory(OFS_FASTPARACHUTE, 0x360080D2); move_p_active = true; }
    } else if (move_p_active) { PatchMemory(OFS_FASTPARACHUTE, 0xF60302AA); move_p_active = false; }
    
    if (move_autoclimb) {
        if (!move_c_active) { PatchMemory(OFS_AUTOCLIMB, 0x360080D2); move_c_active = true; }
    } else if (move_c_active) { PatchMemory(OFS_AUTOCLIMB, 0xF60302AA); move_c_active = false; }
    
    if (move_walkthrough) {
        if (!move_w_active) { PatchMemory(OFS_WALKTHROUGH, 0x360080D2); move_w_active = true; }
    } else if (move_w_active) { PatchMemory(OFS_WALKTHROUGH, 0xF60302AA); move_w_active = false; }
    
    if (move_underwater) {
        if (!move_u_active) { PatchMemory(OFS_UNDERWATER, 0x360080D2); move_u_active = true; }
    } else if (move_u_active) { PatchMemory(OFS_UNDERWATER, 0xF60302AA); move_u_active = false; }
    
    if (misc_antispectate) {
        if (!misc_a_active) { PatchMemory(OFS_ANTISPECTATE, 0x360080D2); misc_a_active = true; }
    } else if (misc_a_active) { PatchMemory(OFS_ANTISPECTATE, 0xF60302AA); misc_a_active = false; }
    
    if (misc_grave) {
        if (!misc_g_active) { PatchMemory(OFS_GRAVE, 0x360080D2); misc_g_active = true; }
    } else if (misc_g_active) { PatchMemory(OFS_GRAVE, 0xF60302AA); misc_g_active = false; }
    
    ImGui::Render();
    
    id<MTLCommandBuffer> commandBuffer = [view.commandQueue commandBuffer];
    MTLRenderPassDescriptor* renderPassDescriptor = view.currentRenderPassDescriptor;
    if (renderPassDescriptor != nil) {
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        [renderEncoder pushDebugGroup:@"ImGui Render"];
        ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, renderEncoder);
        [renderEncoder popDebugGroup];
        [renderEncoder endEncoding];
        [commandBuffer presentDrawable:view.currentDrawable];
    }
    [commandBuffer commit];
}

@end

__attribute__((constructor))
static void InitModMenu() {
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            UIWindow *window = nil;
            if (@available(iOS 13.0, *)) {
                for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if (scene.activationState == UISceneActivationStateForegroundActive) {
                        window = scene.windows.firstObject;
                        break;
                    }
                }
            }
            if (!window) window = [UIApplication sharedApplication].keyWindow;
            if (!window || !window.rootViewController) return;
            ImGuiDrawView *vc = [[ImGuiDrawView alloc] initWithNibName:nil bundle:nil];
            vc.view.frame = window.bounds;
            vc.view.backgroundColor = [UIColor clearColor];
            vc.view.layer.zPosition = 1000;
            [window.rootViewController addChildViewController:vc];
            [window.rootViewController.view addSubview:vc.view];
            [vc didMoveToParentViewController:window.rootViewController];
        }
    );
}
