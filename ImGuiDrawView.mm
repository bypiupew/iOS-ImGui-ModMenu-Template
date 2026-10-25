#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <Foundation/Foundation.h>
//Imgui library
#import "Esp/CaptainHook.h"
#import "Esp/ImGuiDrawView.h"
#import "IMGUI/imgui.h"
#import "IMGUI/imgui_impl_metal.h"
#import "IMGUI/Honkai.h"
//Patch library
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
//  OFFSET MAP — Ros Legacy (client binary)
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
    if (!base) {
        base = (uintptr_t)[[NSBundle mainBundle] executablePath].length;
        // use getRealOffset from template
        base = getRealOffset(0x0);
    }
    return base;
}

static float readFloat(uintptr_t offset) {
    return *(float *)(getBase() + offset);
}

static bool WorldToScreen(Vector3 pos, Vector2 &screen, float *vm, float w, float h) {
    float x = vm[0]*pos.x + vm[4]*pos.y + vm[8]*pos.z  + vm[12];
    float y = vm[1]*pos.x + vm[5]*pos.y + vm[9]*pos.z  + vm[13];
    float z = vm[3]*pos.x + vm[7]*pos.y + vm[11]*pos.z + vm[15];
    if (z < 0.01f) return false;
    screen.x = (w / 2.f) * (1.f + x / z);
    screen.y = (h / 2.f) * (1.f - y / z);
    return true;
}

@interface ImGuiDrawView () <MTKViewDelegate>
@property (nonatomic, strong) id <MTLDevice> device;
@property (nonatomic, strong) id <MTLCommandQueue> commandQueue;
@end

@implementation ImGuiDrawView

void (*huy)(void *instance);
void _huy(void *instance) { huy(instance); }

static bool MenDeal = true;

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    _device = MTLCreateSystemDefaultDevice();
    _commandQueue = [_device newCommandQueue];
    if (!self.device) abort();
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO(); (void)io;
    ImGui::StyleColorsDark();
    ImFont* font = io.Fonts->AddFontFromMemoryCompressedTTF(
        (void*)Honkai_compressed_data, Honkai_compressed_size,
        38.0f, NULL, io.Fonts->GetGlyphRangesDefault());
    ImGui_ImplMetal_Init(_device);
    return self;
}

+ (void)showChange:(BOOL)open { MenDeal = open; }

- (MTKView *)mtkView { return (MTKView *)self.view; }

- (void)loadView {
    CGFloat w = [UIApplication sharedApplication].windows[0].rootViewController.view.frame.size.width;
    CGFloat h = [UIApplication sharedApplication].windows[0].rootViewController.view.frame.size.height;
    self.view = [[MTKView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.mtkView.device = self.device;
    self.mtkView.delegate = self;
    self.mtkView.clearColor = MTLClearColorMake(0, 0, 0, 0);
    self.mtkView.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0];
    self.mtkView.clipsToBounds = YES;
}

- (void)updateIOWithTouchEvent:(UIEvent *)event {
    UITouch *anyTouch = event.allTouches.anyObject;
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

- (void)drawInMTKView:(MTKView*)view
{
    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize.x = view.bounds.size.width;
    io.DisplaySize.y = view.bounds.size.height;
    CGFloat framebufferScale = view.window.screen.scale ?: UIScreen.mainScreen.scale;
    io.DisplayFramebufferScale = ImVec2(framebufferScale, framebufferScale);
    io.DeltaTime = 1 / float(view.preferredFramesPerSecond ?: 120);

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];

    // ═══ TAB BOOLS ═══════════════════════════════════════
    // ESP
    static bool esp_boxes        = false;
    static bool esp_health       = false;
    static bool esp_distance     = false;
    static bool esp_skeleton     = false;
    static bool esp_active       = false;

    // AIM
    static bool aim_assist       = false;
    static bool aim_triggerbot   = false;
    static bool aim_active       = false;
    static float aim_fov         = 80.0f;
    static float aim_smooth      = 5.0f;

    // MOVEMENT
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

    // MISC
    static bool misc_antispectate = false;
    static bool misc_grave        = false;
    static bool misc_a_active     = false;
    static bool misc_g_active     = false;

    [self.view setUserInteractionEnabled:(MenDeal ? YES : NO)];

    MTLRenderPassDescriptor* renderPassDescriptor = view.currentRenderPassDescriptor;
    if (renderPassDescriptor != nil)
    {
        id <MTLRenderCommandEncoder> renderEncoder =
            [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        [renderEncoder pushDebugGroup:@"ROS MOD MENU"];

        ImGui_ImplMetal_NewFrame(renderPassDescriptor);
        ImGui::NewFrame();

        ImFont* font = ImGui::GetFont();
        font->Scale = 15.f / font->FontSize;

        CGFloat sw = [UIApplication sharedApplication].windows[0].rootViewController.view.frame.size.width;
        CGFloat sh = [UIApplication sharedApplication].windows[0].rootViewController.view.frame.size.height;
        CGFloat wx = (sw - 420) / 2;
        CGFloat wy = (sh - 400) / 2;

        ImGui::SetNextWindowPos(ImVec2(wx, wy), ImGuiCond_FirstUseEver);
        ImGui::SetNextWindowSize(ImVec2(420, 420), ImGuiCond_FirstUseEver);

        // ═══════════════════════════════════════════════
        //  MOD MENU UI
        // ═══════════════════════════════════════════════
        if (MenDeal)
        {
            ImGui::PushStyleColor(ImGuiCol_TitleBgActive, ImVec4(0.8f, 0.1f, 0.1f, 1.0f));
            ImGui::PushStyleColor(ImGuiCol_Tab,           ImVec4(0.2f, 0.2f, 0.2f, 1.0f));
            ImGui::PushStyleColor(ImGuiCol_TabActive,     ImVec4(0.8f, 0.1f, 0.1f, 1.0f));

            ImGui::Begin("ROS MOD MENU | 3-Finger Tap to Toggle", &MenDeal);
            ImGui::Text("FPS: %.1f", ImGui::GetIO().Framerate);
            ImGui::Separator();

            if (ImGui::BeginTabBar("MainTabs"))
            {
                // ─── TAB 1: ESP ───────────────────────────────
                if (ImGui::BeginTabItem("ESP"))
                {
                    ImGui::Checkbox("Player Boxes",    &esp_boxes);
                    ImGui::Checkbox("Health Bars",     &esp_health);
                    ImGui::Checkbox("Distance",        &esp_distance);
                    ImGui::Checkbox("Skeleton",        &esp_skeleton);
                    ImGui::EndTabItem();
                }

                // ─── TAB 2: AIM ───────────────────────────────
                if (ImGui::BeginTabItem("Aim"))
                {
                    ImGui::Checkbox("Aim Assist",     &aim_assist);
                    ImGui::Checkbox("Triggerbot",     &aim_triggerbot);
                    ImGui::SliderFloat("FOV",         &aim_fov,    10.f, 300.f);
                    ImGui::SliderFloat("Smoothness",  &aim_smooth,  1.f,  20.f);
                    ImGui::EndTabItem();
                }

                // ─── TAB 3: MOVEMENT ──────────────────────────
                if (ImGui::BeginTabItem("Move"))
                {
                    ImGui::Checkbox("Jump Hack",        &move_jumphack);
                    ImGui::Checkbox("Fast Parachute",   &move_parachute);
                    ImGui::Checkbox("Auto Climb",       &move_autoclimb);
                    ImGui::Checkbox("Walkthrough Walls",&move_walkthrough);
                    ImGui::Checkbox("Underwater",       &move_underwater);
                    ImGui::EndTabItem();
                }

                // ─── TAB 4: MISC ──────────────────────────────
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

        // ═══════════════════════════════════════════════
        //  ESP RENDERING
        // ═══════════════════════════════════════════════
        ImDrawList* draw_list = ImGui::GetBackgroundDrawList();

        if (esp_boxes || esp_health || esp_distance || esp_skeleton)
        {
            // Read ViewMatrix (16 floats)
            float vm[16];
            uintptr_t vmBase = getBase() + OFS_VIEWMATRIX;
            for (int i = 0; i < 16; i++)
                vm[i] = *(float *)(vmBase + i * 4);

            // Local player position
            float lx = readFloat(OFS_PLAYER_X);
            float ly = readFloat(OFS_PLAYER_Y);
            float lz = readFloat(OFS_PLAYER_Z);

            // Entity list
            uintptr_t entityList = *(uintptr_t *)(getBase() + OFS_ENTITYLIST);
            if (entityList) {
                for (int i = 0; i < 100; i++) {
                    uintptr_t entity = *(uintptr_t *)(entityList + i * 0x8);
                    if (!entity) continue;

                    // Entity position
                    float ex = *(float *)(entity + 0xDC);
                    float ey = *(float *)(entity + 0xE0);
                    float ez = *(float *)(entity + 0xE4);

                    // Sanity check
                    if (fabsf(ex) > 100000 || fabsf(ey) > 100000 || fabsf(ez) > 100000) continue;

                    // Distance
                    float dist = sqrtf(powf(ex-lx,2)+powf(ey-ly,2)+powf(ez-lz,2));
                    if (dist > 800.f) continue;

                    // World to screen — feet
                    Vector3 feetPos = {ex, ey, ez};
                    Vector3 headPos = {ex, ey + 1.8f, ez};
                    Vector2 screenFeet, screenHead;

                    if (!WorldToScreen(feetPos, screenFeet, vm, sw, sh)) continue;
                    if (!WorldToScreen(headPos, screenHead, vm, sw, sh)) continue;

                    float boxH = fabsf(screenFeet.y - screenHead.y);
                    float boxW = boxH * 0.4f;

                    // ── Boxes ──
                    if (esp_boxes) {
                        ImU32 col = IM_COL32(255, 50, 50, 220);
                        draw_list->AddRect(
                            ImVec2(screenHead.x - boxW/2, screenHead.y),
                            ImVec2(screenHead.x + boxW/2, screenFeet.y),
                            col, 0.f, 0, 2.0f);
                    }

                    // ── Health bar ──
                    if (esp_health) {
                        float health = 100.f; // placeholder — add health offset when found
                        float healthPct = health / 100.f;
                        ImU32 colBg  = IM_COL32(50,  50,  50,  200);
                        ImU32 colHp  = IM_COL32(50,  255, 50,  220);
                        float barX   = screenHead.x - boxW/2 - 6.f;
                        draw_list->AddRectFilled(
                            ImVec2(barX - 3, screenHead.y),
                            ImVec2(barX,     screenFeet.y),
                            colBg);
                        draw_list->AddRectFilled(
                            ImVec2(barX - 3, screenFeet.y - boxH * healthPct),
                            ImVec2(barX,     screenFeet.y),
                            colHp);
                    }

                    // ── Distance ──
                    if (esp_distance) {
                        char distStr[32];
                        snprintf(distStr, sizeof(distStr), "%.0fm", dist);
                        draw_list->AddText(
                            ImVec2(screenHead.x - 12, screenFeet.y + 2),
                            IM_COL32(255,255,255,220), distStr);
                    }

                    // ── Skeleton ──
                    if (esp_skeleton) {
                        // Basic skeleton — head to chest to feet line
                        draw_list->AddLine(
                            ImVec2(screenHead.x, screenHead.y),
                            ImVec2(screenFeet.x, screenFeet.y),
                            IM_COL32(255,200,0,180), 1.5f);
                    }
                }
            }
        }

        // ── Aim FOV circle ──
        if (aim_assist) {
            draw_list->AddCircle(
                ImVec2(sw/2, sh/2),
                aim_fov,
                IM_COL32(255,255,255,120),
                64, 1.5f);
        }

        // ═══════════════════════════════════════════════
        //  PATCH LOGIC
        // ═══════════════════════════════════════════════

        // Jump Hack
        if (move_jumphack) {
            if (!move_j_active) {
                vm(ENCRYPTOFFSET("0x543CF2"), strtoul(ENCRYPTHEX("0x360080D2"), nullptr, 0));
                move_j_active = true;
            }
        } else {
            if (move_j_active) {
                vm(ENCRYPTOFFSET("0x543CF2"), strtoul(ENCRYPTHEX("0xF60302AA"), nullptr, 0));
                move_j_active = false;
            }
        }

        // Fast Parachute
        if (move_parachute) {
            if (!move_p_active) {
                vm(ENCRYPTOFFSET("0x21992EC"), strtoul(ENCRYPTHEX("0x360080D2"), nullptr, 0));
                move_p_active = true;
            }
        } else {
            if (move_p_active) {
                vm(ENCRYPTOFFSET("0x21992EC"), strtoul(ENCRYPTHEX("0xF60302AA"), nullptr, 0));
                move_p_active = false;
            }
        }

        // Auto Climb
        if (move_autoclimb) {
            if (!move_c_active) {
                vm(ENCRYPTOFFSET("0x5445B0"), strtoul(ENCRYPTHEX("0x360080D2"), nullptr, 0));
                move_c_active = true;
            }
        } else {
            if (move_c_active) {
                vm(ENCRYPTOFFSET("0x5445B0"), strtoul(ENCRYPTHEX("0xF60302AA"), nullptr, 0));
                move_c_active = false;
            }
        }

        // Walkthrough Walls
        if (move_walkthrough) {
            if (!move_w_active) {
                vm(ENCRYPTOFFSET("0x175EF68"), strtoul(ENCRYPTHEX("0x360080D2"), nullptr, 0));
                move_w_active = true;
            }
        } else {
            if (move_w_active) {
                vm(ENCRYPTOFFSET("0x175EF68"), strtoul(ENCRYPTHEX("0xF60302AA"), nullptr, 0));
                move_w_active = false;
            }
        }

        // Underwater
        if (move_underwater) {
            if (!move_u_active) {
                vm(ENCRYPTOFFSET("0x396F8C"), strtoul(ENCRYPTHEX("0x360080D2"), nullptr, 0));
                move_u_active = true;
            }
        } else {
            if (move_u_active) {
                vm(ENCRYPTOFFSET("0x396F8C"), strtoul(ENCRYPTHEX("0xF60302AA"), nullptr, 0));
                move_u_active = false;
            }
        }

        // Anti-Spectate
        if (misc_antispectate) {
            if (!misc_a_active) {
                vm(ENCRYPTOFFSET("0x12D486"), strtoul(ENCRYPTHEX("0x360080D2"), nullptr, 0));
                misc_a_active = true;
            }
        } else {
            if (misc_a_active) {
                vm(ENCRYPTOFFSET("0x12D486"), strtoul(ENCRYPTHEX("0xF60302AA"), nullptr, 0));
                misc_a_active = false;
            }
        }

        // Grave
        if (misc_grave) {
            if (!misc_g_active) {
                vm(ENCRYPTOFFSET("0x545018"), strtoul(ENCRYPTHEX("0x360080D2"), nullptr, 0));
                misc_g_active = true;
            }
        } else {
            if (misc_g_active) {
                vm(ENCRYPTOFFSET("0x545018"), strtoul(ENCRYPTHEX("0xF60302AA"), nullptr, 0));
                misc_g_active = false;
            }
        }

        // Dobby hook — runs once
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            DobbyHook(
                (void *)(getRealOffset(ENCRYPTOFFSET("0x5F145F8"))),
                (void *)_huy, (void **)&huy);
        });

        // ═══════════════════════════════════════════════
        //  RENDER
        // ═══════════════════════════════════════════════
        ImGui::Render();
        ImDrawData* draw_data = ImGui::GetDrawData();
        ImGui_ImplMetal_RenderDrawData(draw_data, commandBuffer, renderEncoder);

        [renderEncoder popDebugGroup];
        [renderEncoder endEncoding];
        [commandBuffer presentDrawable:view.currentDrawable];
    }
    [commandBuffer commit];
}

- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {}

@end
