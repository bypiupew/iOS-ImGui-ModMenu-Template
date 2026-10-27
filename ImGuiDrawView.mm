#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Imgui library
#import "Esp/CaptainHook.h"
#import "Esp/ImGuiDrawView.h"
#import "IMGUI/imgui.h"
#import "IMGUI/imgui_internal.h"
#import "IMGUI/imgui_impl_metal.h"
#import "IMGUI/Honkai.h"

// Patch library
#import "5Toubun/NakanoIchika.h"
#import "5Toubun/NakanoNino.h"
#import "5Toubun/NakanoMiku.h"
#import "5Toubun/NakanoYotsuba.h"
#import "5Toubun/NakanoItsuki.h"
#import "5Toubun/dobby.h"

#define kWidth  [UIScreen mainScreen].bounds.size.width
#define kHeight [UIScreen mainScreen].bounds.size.height
#define kScale  [UIScreen mainScreen].scale

// ═══════════════════════════════════════════════════════
//  OFFSET MAP — MyBattleRoyale (client binary)
// ═══════════════════════════════════════════════════════
#define OFS_VIEWMATRIX      0x1ED79B0
#define OFS_LOCALPLAYER     0x20E435C
#define OFS_PLAYER_X        0x1F8D330
#define OFS_PLAYER_Y        0x1F8D334
#define OFS_PLAYER_Z        0x1F8D338
#define OFS_PLAYER_PITCH    0x1F8D33C
#define OFS_PLAYER_YAW      0x1F8D340
#define OFS_SKELETON        0x20E66FC
#define OFS_ENTITYLIST      0x20D6C50
#define OFS_CLIENT          0x20E2578
#define OFS_RENDER          0x20D6B48
#define OFS_JUMPHACK        0x543CF2
#define OFS_FASTPARACHUTE   0x21992EC
#define OFS_AUTOCLIMB       0x5445B0
#define OFS_WALKTHROUGH     0x175EF68
#define OFS_ANTISPECTATE    0x12D486
#define OFS_GRAVE           0x545018
#define OFS_UNDERWATER      0x396F8C

// ═══════════════════════════════════════════════════════
//  WORLD TO SCREEN
// ═══════════════════════════════════════════════════════
struct Vector3 { float x, y, z; };
struct Vector2 { float x, y; };

static uintptr_t getBase() {
    static uintptr_t base = 0;
    if (!base) base = getRealOffset(0x0);
    return base;
}

static float readFloat(uintptr_t offset) {
    uintptr_t base = getBase();
    if (!base) return 0.f;
    return *(float *)(base + offset);
}

static void PatchMemory(uintptr_t offset, uint32_t instruction) {
    uintptr_t base = getBase();
    if (!base) return;
    uintptr_t targetAddress = base + offset;
    DobbyCodePatch((void *)targetAddress, (uint8_t *)&instruction, sizeof(instruction));
}

static bool WorldToScreen(Vector3 pos, Vector2 &screen, float *vm, float w, float h) {
    float x  = vm[0]*pos.x + vm[4]*pos.y + vm[8]*pos.z  + vm[12];
    float y  = vm[1]*pos.x + vm[5]*pos.y + vm[9]*pos.z  + vm[13];
    float z  = vm[3]*pos.x + vm[7]*pos.y + vm[11]*pos.z + vm[15];
    if (z < 0.01f) return false;
    screen.x = (w / 2.f) * (1.f + x / z);
    screen.y = (h / 2.f) * (1.f - y / z);
    return true;
}

@interface ImGuiDrawView () <MTKViewDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) id <MTLDevice> device;
@property (nonatomic, strong) id <MTLCommandQueue> commandQueue;
@end

@implementation ImGuiDrawView

static bool MenDeal = false; 

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (!self) return nil;
    
    _device = MTLCreateSystemDefaultDevice();
    if (!_device) abort();
    
    _commandQueue = [_device newCommandQueue];
    if (!_commandQueue) abort();

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO(); (void)io;
    ImGui::StyleColorsDark();
    
    if (Honkai_compressed_size > 0) {
        io.Fonts->AddFontFromMemoryCompressedTTF(
            (void*)Honkai_compressed_data, Honkai_compressed_size,
            38.0f, NULL, io.Fonts->GetGlyphRangesDefault());
    }
    
    ImGui_ImplMetal_Init(_device);
    return self;
}

+ (void)showChange:(BOOL)open {
    MenDeal = open;
}

- (void)handleShowMenu:(UITapGestureRecognizer *)gesture {
    MenDeal = YES;
}

- (void)handleHideMenu:(UITapGestureRecognizer *)gesture {
    MenDeal = NO;
}

- (MTKView *)mtkView { return (MTKView *)self.view; }

- (void)loadView {
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    MTKView *mv = [[MTKView alloc] initWithFrame:screenBounds];
    mv.userInteractionEnabled = YES; 
    mv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = mv;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    MTKView *mtk = self.mtkView;
    if (mtk) {
        mtk.device = self.device;
        mtk.delegate = self;
        mtk.clearColor = MTLClearColorMake(0, 0, 0, 0);
        mtk.backgroundColor = [UIColor clearColor];
        mtk.clipsToBounds = YES;
        mtk.layer.zPosition = 1000;
        mtk.framebufferOnly = NO;
    }
    
    UITapGestureRecognizer *showTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleShowMenu:)];
    showTap.numberOfTapsRequired = 2;
    showTap.numberOfTouchesRequired = 3;
    showTap.delegate = self;
    [self.view addGestureRecognizer:showTap];

    UITapGestureRecognizer *hideTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleHideMenu:)];
    hideTap.numberOfTapsRequired = 2;
    hideTap.numberOfTouchesRequired = 2;
    hideTap.delegate = self;
    [self.view addGestureRecognizer:hideTap];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

#pragma mark - Touch passthrough

- (void)updateIOWithTouchEvent:(UIEvent *)event
{
    if (!MenDeal) return;
    UITouch *anyTouch = event.allTouches.anyObject;
    if (!anyTouch) return;
    CGPoint touchLocation = [anyTouch locationInView:self.view];
    ImGuiIO &io = ImGui::GetIO();
    io.MousePos = ImVec2(touchLocation.x, touchLocation.y);
    BOOL hasActiveTouch = NO;
    for (UITouch *touch in event.allTouches) {
        if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled) {
            hasActiveTouch = YES; break;
        }
    }
    io.MouseDown[0] = hasActiveTouch;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event    { [self updateIOWithTouchEvent:event]; }
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event    { [self updateIOWithTouchEvent:event]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{ [self updateIOWithTouchEvent:event]; }
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event    { [self updateIOWithTouchEvent:event]; }

#pragma mark - MTKViewDelegate

- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {}

- (void)drawInMTKView:(MTKView*)view
{
    @autoreleasepool {
        ImGuiIO& io = ImGui::GetIO();
        io.DisplaySize.x = view.bounds.size.width;
        io.DisplaySize.y = view.bounds.size.height;
        CGFloat framebufferScale = view.window.screen.scale ?: UIScreen.mainScreen.scale;
        io.DisplayFramebufferScale = ImVec2(framebufferScale, framebufferScale);
        io.DeltaTime = 1.0f / (view.preferredFramesPerSecond > 0 ? view.preferredFramesPerSecond : 60.0f);

        if (!self.commandQueue) return;
        id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
        if (!commandBuffer) return;

        static bool esp_boxes        = false;
        static bool esp_health       = false;
        static bool esp_distance     = false;
        static bool esp_skeleton     = false;

        static bool aim_assist       = false;
        static bool aim_triggerbot   = false;
        static float aim_fov         = 80.0f;
        static float aim_smooth      = 5.0f;

        static bool move_jumphack    = false;
        static bool move_parachute   = false;
        static bool move_autoclimb   = false;
        static bool move_walkthrough = false;
        static bool move_underwater  = false;
        static bool move_j_active    = false;
        static bool move_p_active    = false;
        static bool move_c_active    = false;
        static bool move_w_active    = false;
        static bool move_u_active    = false;

        static bool misc_antispectate = false;
        static bool misc_grave        = false;
        static bool misc_a_active     = false;
        static bool misc_g_active     = false;

        MTLRenderPassDescriptor* renderPassDescriptor = view.currentRenderPassDescriptor;
        if (renderPassDescriptor != nil)
        {
            id <MTLRenderCommandEncoder> renderEncoder =
                [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
            if (renderEncoder) {
                [renderEncoder pushDebugGroup:@"ROS MOD MENU"];

                ImGui_ImplMetal_NewFrame(renderPassDescriptor);
                ImGui::NewFrame();

                ImFont* font = ImGui::GetFont();
                if (font) font->Scale = 15.f / font->FontSize;

                CGFloat sw = view.bounds.size.width;
                CGFloat sh = view.bounds.size.height;

                if (MenDeal)
                {
                    CGFloat wx = (sw - 420) / 2;
                    CGFloat wy = (sh - 420) / 2;
                    ImGui::SetNextWindowPos(ImVec2(wx, wy), ImGuiCond_FirstUseEver);
                    ImGui::SetNextWindowSize(ImVec2(420, 420), ImGuiCond_FirstUseEver);

                    ImGui::PushStyleColor(ImGuiCol_TitleBgActive, ImVec4(0.8f, 0.1f, 0.1f, 1.0f));
                    ImGui::PushStyleColor(ImGuiCol_Tab,           ImVec4(0.2f, 0.2f, 0.2f, 1.0f));
                    ImGui::PushStyleColor(ImGuiCol_TabActive,     ImVec4(0.8f, 0.1f, 0.1f, 1.0f));

                    ImGui::Begin("ROS MOD MENU | 3-Finger Double Tap", &MenDeal);
                    ImGui::Text("FPS: %.1f", ImGui::GetIO().Framerate);
                    ImGui::Separator();

                    if (ImGui::BeginTabBar("MainTabs"))
                    {
                        if (ImGui::BeginTabItem("ESP"))
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
                    ImGui::PopStyleColor(3);
                }

                ImDrawList* draw_list = ImGui::GetBackgroundDrawList();
                if (esp_boxes || esp_health || esp_distance || esp_skeleton)
                {
                    uintptr_t vmBase = getBase();
                    if (vmBase) {
                        vmBase += OFS_VIEWMATRIX;
                        float vm[16];
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
                ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, renderEncoder);
                [renderEncoder popDebugGroup];
                [renderEncoder endEncoding];
                if (view.currentDrawable) {
                    [commandBuffer presentDrawable:view.currentDrawable];
                }
            }
        }
        [commandBuffer commit];
    }
}

@end

// ═══════════════════════════════════════════════════════
//  CONSTRUCTOR
// ═══════════════════════════════════════════════════════
__attribute__((constructor))
static void InitModMenu() {
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            UIWindow *targetWindow = nil;
            if (@available(iOS 13.0, *)) {
                for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if (scene.activationState == UISceneActivationStateForegroundActive) {
                        for (UIWindow *win in scene.windows) {
                            if (win.isKeyWindow) {
                                targetWindow = win;
                                break;
                            }
                        }
                        if (!targetWindow) {
                            targetWindow = scene.windows.firstObject;
                        }
                        if (targetWindow) break;
                    }
                }
            }
            if (!targetWindow) {
                targetWindow = [UIApplication sharedApplication].keyWindow;
            }
            
            if (targetWindow && targetWindow.rootViewController) {
                ImGuiDrawView *vc = [[ImGuiDrawView alloc] initWithNibName:nil bundle:nil];
                vc.view.frame = targetWindow.bounds;
                vc.view.backgroundColor = [UIColor clearColor];
                vc.view.layer.zPosition = 1000;
                [targetWindow.rootViewController addChildViewController:vc];
                [targetWindow.rootViewController.view addSubview:vc.view];
                [vc didMoveToParentViewController:targetWindow.rootViewController];
            } else {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    UIWindow *fallbackWindow = [UIApplication sharedApplication].keyWindow;
                    if (fallbackWindow && fallbackWindow.rootViewController) {
                        ImGuiDrawView *vc = [[ImGuiDrawView alloc] initWithNibName:nil bundle:nil];
                        vc.view.frame = fallbackWindow.bounds;
                        vc.view.backgroundColor = [UIColor clearColor];
                        vc.view.layer.zPosition = 1000;
                        [fallbackWindow.rootViewController addChildViewController:vc];
                        [fallbackWindow.rootViewController.view addSubview:vc.view];
                        [vc didMoveToParentViewController:fallbackWindow.rootViewController];
                    }
                });
            }
        }
    );
}
