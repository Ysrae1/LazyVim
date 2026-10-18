/* Static Notebook viewer: no kernel or output scripts are executed. */
(() => {
  'use strict';
  const notebook = JSON.parse(document.getElementById('notebook-data').textContent);
  const md = window.markdownit({html:false, linkify:false, typographer:false});
  const text = value => Array.isArray(value) ? value.join('') : (typeof value === 'string' ? value : '');
  const math = (source, display) => katex.renderToString(source, {
    displayMode:display, throwOnError:false, trust:false, strict:'ignore', maxExpand:1000, maxSize:20
  });
  md.inline.ruler.before('escape', 'notebook_math', (state, silent) => {
    const start = state.pos;
    const tail = state.src.slice(start);
    const opener = ['$$','\\[','\\(','$'].find(value => tail.startsWith(value));
    if (!opener || (opener === '$' && /\s/.test(tail[1] || ' '))) return false;
    const closer = opener === '\\[' ? '\\]' : opener === '\\(' ? '\\)' : opener;
    let end = start + opener.length;
    while ((end = state.src.indexOf(closer, end)) >= 0 && state.src[end - 1] === '\\') end += closer.length;
    if (end < 0 || (opener === '$' && /\s/.test(state.src[end - 1]))) return false;
    if (!silent) {
      const token = state.push('notebook_math','math',0);
      token.content = state.src.slice(start + opener.length, end);
      token.block = opener === '$$' || opener === '\\[';
    }
    state.pos = end + closer.length;
    return true;
  });
  md.renderer.rules.notebook_math = (tokens, index) => math(tokens[index].content,tokens[index].block);
  md.block.ruler.before('fence', 'notebook_math_block', (state,startLine,endLine,silent) => {
    const start = state.bMarks[startLine] + state.tShift[startLine];
    const line = state.src.slice(start,state.eMarks[startLine]);
    const opener = line.startsWith('$$') ? '$$' : line.startsWith('\\[') ? '\\[' : null;
    if (!opener) return false;
    const closer = opener === '$$' ? '$$' : '\\]';
    const end = state.src.indexOf(closer,start + 2);
    if (end < 0) return false;
    let nextLine = startLine;
    while (nextLine < endLine && state.eMarks[nextLine] < end + 2) nextLine++;
    if (nextLine === endLine || state.src.slice(end + 2,state.eMarks[nextLine]).trim()) return false;
    if (silent) return true;
    const token = state.push('notebook_math','math',0);
    token.content = state.src.slice(start + 2,end);
    token.block = true;
    token.map = [startLine,nextLine + 1];
    state.line = nextLine + 1;
    return true;
  });
  const element = (tag,cls,content) => {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (content !== undefined) node.textContent = content;
    return node;
  };
  const pre = value => element('pre','',text(value).replace(/\x1b\[[0-9;]*[A-Za-z]/g,''));
  const image = (mime,value) => {
    const img = element('img','output-image');
    img.alt = mime === 'image/png' ? '已保存的 PNG 图表' : '已保存的 SVG 图表';
    img.src = 'data:' + mime + ';base64,' + (mime === 'image/svg+xml' ? btoa(unescape(encodeURIComponent(text(value)))) : text(value).replace(/\s/g,''));
    return img;
  };
  const staticHTML = value => {
    const frame = element('iframe','html-output');
    frame.title = '已保存的静态 HTML 输出（脚本停用）';
    frame.setAttribute('sandbox','');
    frame.srcdoc = '<!doctype html><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'; img-src data: file:; font-src data:;"><style>body{font:14px -apple-system,BlinkMacSystemFont,sans-serif;margin:12px;color:#20242a;background:#fff}table{border-collapse:collapse}th,td{border:1px solid #d7dce2;padding:6px 10px}img,svg{max-width:100%;height:auto}pre{white-space:pre-wrap}</style>' + text(value);
    return frame;
  };
  const output = item => {
    const box = element('div','output');
    if (item.output_type === 'stream') {
      if (item.name === 'stderr') box.classList.add('stderr');
      box.append(pre(item.text));
    } else if (item.output_type === 'error') {
      box.classList.add('stderr');
      box.append(pre(item.traceback || ((item.ename || 'Error') + ': ' + (item.evalue || ''))));
    } else {
      const data = item.data || {};
      const mime = ['text/html','image/svg+xml','image/png','text/markdown','text/latex','application/json','text/plain'].find(key => data[key] !== undefined);
      if (mime === 'text/html') box.append(staticHTML(data[mime]));
      else if (mime === 'image/png' || mime === 'image/svg+xml') box.append(image(mime,data[mime]));
      else if (mime === 'text/markdown') {
        const node = element('div','markdown'); node.innerHTML = md.render(text(data[mime])); box.append(node);
      } else if (mime === 'text/latex') {
        const node = element('div','latex-output');
        const source = text(data[mime]).replace(/^\s*(\$\$|\$|\\\[|\\\()/,'').replace(/(\$\$|\$|\\\]|\\\))\s*$/,'');
        node.innerHTML = math(source,true); box.append(node);
      } else if (mime === 'application/json') box.append(pre(JSON.stringify(data[mime],null,2)));
      else if (mime) box.append(pre(data[mime]));
      else box.append(element('p','muted','此输出没有可显示的已保存静态内容。'));
    }
    return box;
  };
  const main = document.getElementById('cells');
  const language = notebook.metadata && notebook.metadata.language_info && notebook.metadata.language_info.name || '代码';
  notebook.cells.forEach((cell,index) => {
    const section = element('section','cell ' + cell.cell_type);
    section.dataset.cell = String(index + 1);
    section.append(element('div','cell-label',(index + 1) + ' · ' + (cell.cell_type === 'code' ? language + ' [' + (cell.execution_count == null ? ' ' : cell.execution_count) + ']' : cell.cell_type === 'markdown' ? 'Markdown' : '原始文本')));
    if (cell.cell_type === 'markdown') {
      const body = element('div','markdown');
      body.innerHTML = md.render(text(cell.source));
      body.querySelectorAll('img').forEach(img => {
        const src = img.getAttribute('src') || '';
        if (!src.startsWith('attachment:')) return;
        const data = (cell.attachments || {})[decodeURIComponent(src.slice(11))] || {};
        const mime = ['image/png','image/jpeg','image/svg+xml'].find(key => data[key]);
        if (mime) img.src = image(mime,data[mime]).src;
      });
      section.append(body);
    } else {
      const source = pre(cell.source);
      source.className = 'source';
      section.append(source);
      (cell.outputs || []).forEach(item => section.append(output(item)));
    }
    main.append(section);
  });
  document.getElementById('count').textContent = notebook.cells.length + ' 个单元格 · 保存输出查看';
  document.documentElement.dataset.rendered = 'true';
})();
