-- JPEG XL decoder for the private Neovide Yazi overlay. djxl decodes pixels;
-- existing ImageMagick only resizes PNG, so its missing JXL codec is irrelevant.
local M = {}
local INPUT_LIMIT, PIXEL_LIMIT, MEMORY_LIMIT = 64 * 1024 * 1024, 32 * 1024 * 1024, 512 * 1024 * 1024

local function cache_for(job)
  local base = ya.file_cache(job)
  if not base then return nil end
  return Url(tostring(base) .. ".glow-jxl-v1-" .. rt.preview.max_width .. "x" .. rt.preview.max_height .. ".png")
end

local function run(command, memory)
  local child, err = command:memory(memory):spawn()
  if not child then return nil, err end
  local started = ya.time()
  while true do
    local status, wait_error = child:try_wait()
    if status or wait_error then return status, wait_error end
    local id = child:id()
    local process = id and ya.proc_info(id)
    local resident = process and process.mem_resident
    if resident and resident > memory then
      child:start_kill()
      return nil, Err("JPEG XL 解码超过内存限制")
    elseif ya.time() - started > 20 then
      child:start_kill()
      return nil, Err("JPEG XL 转换超过 20 秒限制")
    end
    ya.sleep(0.05)
  end
end

function M:preload(job)
  local cache = cache_for(job)
  if not cache then return false, Err("JPEG XL 无法建立预览缓存") end
  local cached = fs.cha(cache)
  if cached and cached.len > 0 then return true end
  if job.file.cha.len > INPUT_LIMIT then return false, Err("JPEG XL 文件超过 64 MiB 预览限制") end
  local input = tostring(job.file.path)
  local args = job.args or {}
  local info, err = Command(args.inspector or "jxlinfo"):arg(input):stdout(Command.PIPED):stderr(Command.PIPED):output()
  if not info then return false, Err("JPEG XL 无法启动 jxlinfo：%s", err) end
  if not info.status.success then return false, Err("JPEG XL 文件无效：%s", (info.stderr or ""):sub(1, 500)) end
  local width, height = info.stdout:match("(%d+)x(%d+)")
  width, height = tonumber(width), tonumber(height)
  local memory = math.min(MEMORY_LIMIT, rt.tasks.image_alloc > 0 and rt.tasks.image_alloc or MEMORY_LIMIT)
  local pixels = math.min(PIXEL_LIMIT, math.floor(memory / 16))
  if not width or not height then return false, Err("JPEG XL 文件无效：不能读取图像尺寸") end
  if width < 1 or height < 1 or width * height > pixels then
    return false, Err("JPEG XL 解码尺寸超过 %d 像素预览限制", pixels)
  end
  local work = os.getenv("YAZI_CONFIG_HOME") .. "/jxl-work/" .. ya.hash(tostring(cache) .. ya.time())
  local raw, resized = Url(work .. ".raw.png"), Url(work .. ".cache.png")
  local function finish(success, failure)
    fs.remove("file", raw)
    fs.remove("file", resized)
    return success, failure
  end
  local decoded, decode_error = run(Command(args.decoder or "djxl"):arg {
    input, tostring(raw), "--output_format=png", "--num_threads=1", "--bits_per_sample=8", "--quiet",
  }, memory)
  if not decoded then return finish(false, Err("JPEG XL 无法解码：%s", decode_error)) end
  if not decoded.success then return finish(false, Err("JPEG XL djxl 解码失败，退出码 %s", decoded.code)) end
  local resized_status, resize_error = run(Command(args.magick or "magick"):arg {
    "-limit", "thread", "1", "-limit", "memory", tostring(memory), "-limit", "disk", "1MiB",
    tostring(raw), "-thumbnail", string.format("%dx%d>", rt.preview.max_width, rt.preview.max_height),
    "-strip", "PNG:" .. tostring(resized),
  }, memory)
  if not resized_status then return finish(false, Err("JPEG XL 无法缩放 PNG：%s", resize_error)) end
  if not resized_status.success then return finish(false, Err("JPEG XL PNG 缓存生成失败，退出码 %s", resized_status.code)) end
  local output = ya.image_info(resized)
  if not output or output.w > rt.preview.max_width or output.h > rt.preview.max_height then
    return finish(false, Err("JPEG XL PNG 缓存尺寸无效"))
  end
  local saved, save_error = fs.rename(resized, cache)
  if not saved then return finish(false, Err("JPEG XL 缓存保存失败：%s", save_error)) end
  return finish(true)
end

function M:peek(job)
  local ok, err = self:preload(job)
  if not ok or err then return ya.preview_widget(job, err) end
  local _, show_error = ya.image_show(cache_for(job), job.area)
  ya.preview_widget(job, show_error)
end

function M:seek() end
return M
