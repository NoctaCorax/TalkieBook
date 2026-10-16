import './foliate/view.js';
import { Overlayer } from './foliate/overlayer.js';

const send = (type, data = {}) => window.webkit.messageHandlers.reader.postMessage({type, ...data});
const view = document.createElement('foliate-view');
document.body.append(view);
let prefs = {}, sentences = [], chapter = -1, annotations = [], currentCFI = '', selection = null;
let searchGeneration = 0, opening = false, relocateTimer;
const segmenter = new Intl.Segmenter('pl', {granularity:'sentence'});
const labels = x => typeof x === 'string' ? x : x?.value || '';
const blocked = 'script,style,nav,[hidden],[aria-hidden="true"],svg,math';

function rangesFor(doc) {
    const nodes = [];
    const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT, {acceptNode(node) {
        const parent = node.parentElement;
        if (!parent || parent.closest(blocked)) return NodeFilter.FILTER_REJECT;
        if (prefs.skipCode && parent.closest('pre')) return NodeFilter.FILTER_REJECT;
        if (prefs.skipNotes && parent.closest('aside,[epub\\:type="footnote"],[role="doc-footnote"],sup')) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
    }});
    for (let n = walker.nextNode(); n; n = walker.nextNode()) nodes.push(n);
    // Keep block boundaries; inline emphasis and links remain in a single sentence.
    const groups = [];
    for (const node of nodes) {
        const block = node.parentElement.closest('p,li,h1,h2,h3,h4,h5,h6,blockquote,pre,td,figcaption') || node.parentElement;
        const last = groups.at(-1);
        if (last?.block === block) last.nodes.push(node);
        else groups.push({block,nodes:[node]});
    }
    const result = [];
    for (const group of groups) {
        let text = '', positions = [];
        for (const node of group.nodes) {positions.push({node,start:text.length,end:text.length+node.length});text += node.textContent;}
        let parts = [...segmenter.segment(text)].map(s => ({start:s.index,end:s.index+s.segment.length,text:s.segment}));
        // Common Polish abbreviations must not turn into standalone audio fragments.
        for (let i=0;i<parts.length-1;i++) {
            if (/(?:\b(?:np|itp|itd|tj|tzn|dr|prof|mgr|ul|al|św|r|nr|str)|\b[A-ZĄĆĘŁŃÓŚŹŻ])\.$/u.test(parts[i].text.trim())) {
                parts[i].end=parts[i+1].end;parts[i].text+=parts[i+1].text;parts.splice(i+1,1);i--;
            }
        }
        for (const part of parts) {
            // Split exceptionally long punctuation-free paragraphs at whitespace.
            let start=part.start;
            while(start<part.end) {
                let end=Math.min(part.end,start+1200);
                if(end<part.end) {const space=text.lastIndexOf(' ',end);if(space>start)end=space+1;}
                const spoken=text.slice(start,end).replace(/[\u00ad\u200b]/g,'').replace(/\s+/g,' ').trim();
                if (spoken && /[\p{L}\p{N}]/u.test(spoken)) {
                    const a=positions.find(p=>p.end>start), b=positions.find(p=>p.end>=end);
                    if(a&&b) {const range=doc.createRange();range.setStart(a.node,Math.max(0,start-a.start));range.setEnd(b.node,end-b.start);result.push({range,text:spoken});}
                }
                start=end;
            }
        }
    }
    return result;
}

function publishChapter(doc,index) {
    chapter=index;
    sentences=rangesFor(doc).map((s,i)=>({...s,id:i,cfi:view.getCFI(index,s.range)}));
    send('sentences',{chapter:index,items:sentences.map(({id,text,cfi})=>({id,text,cfi}))});
}

function styles() {
    const dark=!!prefs.dark;
    const palettes={white:dark?['#1b1c20','#e3e4e7']:['#fffefb','#25262a'],cream:dark?['#25221d','#e9dfce']:['#f6efdf','#383329'],sepia:dark?['#2b211a','#e5cdb0']:['#ead8b9','#463726'],gray:dark?['#202427','#d7dfe1']:['#e8edee','#2e383d']};
    const [bg,fg]=palettes[prefs.paper]||palettes.cream;
    document.documentElement.style.background=bg;
    document.body.style.background=bg;
    view.style.background=bg;
    const font=JSON.stringify(prefs.font||'Charter');
    view.renderer?.setAttribute('flow',prefs.flow==='scrolled'?'scrolled':'paginated');
    view.renderer?.setAttribute('max-column-count',String(prefs.columns||1));
    view.renderer?.setAttribute('max-inline-size','740px');
    view.renderer?.setAttribute('margin','38px');
    view.renderer?.setAttribute('gap',String(prefs.margin||8)+'%');
    view.renderer?.setStyles?.(`:root{color-scheme:${dark?'dark':'light'};--overlayer-highlight-opacity:${dark?'.30':'.26'}}
      html,body{background:${bg}!important;color:${fg}!important}body{font-family:${font},Georgia,serif!important;font-size:${prefs.fontSize||21}px!important;line-height:${prefs.lineHeight||1.65}!important;font-weight:${prefs.bold?'600':'400'}!important;text-align:${prefs.justify?'justify':'start'}!important;letter-spacing:${prefs.letterSpacing||0}em!important;word-spacing:${prefs.wordSpacing||0}em!important}
      body *{color:inherit!important}p,li,blockquote,td{font-family:inherit!important;font-size:1em!important;line-height:inherit!important}p,div,span,li,h1,h2,h3,h4,h5,h6,blockquote,td,pre,code{background-color:transparent!important}p span,li span{font-family:inherit!important;font-size:inherit!important}a,a *{color:${dark?'#b6c6a2':'#537047'}!important}img,svg{max-width:100%!important;height:auto}pre{white-space:pre-wrap!important;overflow-wrap:anywhere}code,pre{font-family:ui-monospace,monospace!important;font-size:.86em!important}h1,h2,h3{line-height:1.25!important}::selection{background:${dark?'#776d45':'#ddd0a3'}}`);
}

view.addEventListener('load',({detail:{doc,index}})=>{
    doc.querySelectorAll('script,iframe,object,embed,form').forEach(el=>el.remove());
    publishChapter(doc,index);
    doc.addEventListener('keydown',keyHandler);
    doc.addEventListener('mouseup',()=>{
        const s=doc.getSelection();
        if(s?.rangeCount&&!s.isCollapsed) {
            const range=s.getRangeAt(0).cloneRange();
            selection={cfi:view.getCFI(index,range),text:s.toString()};
            send('selection',selection);
        }
    });
    doc.addEventListener('contextmenu',e=>{
        e.preventDefault();
        const s=doc.getSelection();
        let range=s?.rangeCount&&!s.isCollapsed?s.getRangeAt(0):doc.caretRangeFromPoint(e.clientX,e.clientY);
        if(!range)return;
        const sentence=sentences.find(s=>{try{return s.range.isPointInRange(range.startContainer,range.startOffset)}catch{return false}});
        if(sentence)send('context',{index:sentence.id,cfi:s?.rangeCount&&!s.isCollapsed?view.getCFI(index,range):sentence.cfi,text:s?.rangeCount&&!s.isCollapsed?s.toString():sentence.text});
    });
    doc.addEventListener('dblclick',()=>send('chrome'));
});
view.addEventListener('relocate',({detail})=>{
    clearTimeout(relocateTimer);
    relocateTimer=setTimeout(()=>{
        const {cfi,fraction,tocItem,section}=detail;
        send('location',{cfi,fraction:fraction||0,label:tocItem?.label||'',chapter:chapter});
    },120);
});
view.addEventListener('create-overlay',()=>{for(const a of annotations)view.addAnnotation(a).catch(()=>{});if(currentCFI)highlight(currentCFI,false)});
view.addEventListener('draw-annotation',({detail:{draw,annotation}})=>draw(Overlayer.highlight,{color:annotation.color||'#d6b65b'}));
view.addEventListener('external-link',e=>{e.preventDefault();send('external',{url:e.detail.href_});});

async function highlight(cfi,follow=true) {
    currentCFI=cfi||'';
    for(const {overlayer} of view.renderer?.getContents()||[])overlayer?.remove('speaking');
    if(!cfi)return;
    const target=view.resolveCFI(cfi);
    if(follow&&prefs.follow)await view.renderer.goTo(target);
    const content=view.renderer.getContents().find(c=>c.index===target.index);
    if(content?.overlayer) {
        const range=target.anchor(content.doc);
        content.overlayer.add('speaking',range,Overlayer.highlight,{color:prefs.dark?'#b7bc87':'#b8bd74'});
    }
}
function visibleStart() {
    const range=view.lastLocation?.range;
    if(!range)return 0;
    const i=sentences.findIndex(s=>s.range.comparePoint(range.startContainer,range.startOffset)<=0);
    return Math.max(0,i);
}
function keyHandler(e) {
    if(e.metaKey||e.ctrlKey||e.altKey)return;
    if(e.key==='ArrowRight'){e.preventDefault();view.goRight();}
    if(e.key==='ArrowLeft'){e.preventDefault();view.goLeft();}
    if(e.key===' '){e.preventDefault();send('togglePlay');}
    if(e.key==='Escape')send('escape');
}
document.addEventListener('keydown',keyHandler);

window.reader={
    async open(url,lastLocation,settings,marks) {
        opening=true;prefs=settings;annotations=marks||[];
        try {
            // WebKit custom-scheme fetch responses may have status 0 despite
            // delivering a valid body. Pass a File instead of foliate's HTTP loader.
            const response=await fetch(url);
            const bytes=await response.arrayBuffer();
            if(!bytes.byteLength)throw new Error(prefs.language==='en'?'The book file is empty.':'Plik książki jest pusty.');
            await view.open(new File([bytes],'book.epub',{type:'application/epub+zip'}));
            styles();
            send('toc',{items:(function flatten(items,depth=0){return(items||[]).flatMap(i=>[{label:labels(i.label),href:i.href,depth},...flatten(i.subitems,depth+1)])})(view.book.toc)});
            await view.init({lastLocation:lastLocation||undefined,showTextStart:true});
            send('opened');
        } catch(e) {send('error',{message:String(e?.message||e)});}finally{opening=false;}
    },
    settings(settings){const changed=prefs.skipCode!==settings.skipCode||prefs.skipNotes!==settings.skipNotes;prefs=settings;styles();if(changed){const c=view.renderer.getContents()[0];if(c)publishChapter(c.doc,c.index);}if(currentCFI)highlight(currentCFI,false);},
    next(){return view.goRight()},prev(){return view.goLeft()},
    go(cfi){return view.goTo(cfi)},fraction(f){return view.goToFraction(f)},
    highlight,
    begin(cfi){const target=cfi?view.resolveCFI(cfi):null;let i=target?sentences.findIndex(s=>s.cfi===cfi):-1;if(i<0)i=visibleStart();send('start',{index:i,chapter});},
    async resume(cfi){await view.goTo(cfi);const target=view.resolveCFI(cfi);const content=view.renderer.getContents().find(c=>c.index===target.index);let i=sentences.findIndex(s=>s.cfi===cfi);if(i<0&&content){const range=target.anchor(content.doc);i=sentences.findIndex(s=>s.range.comparePoint(range.startContainer,range.startOffset)<=0);}send('start',{index:Math.max(0,i),chapter});},
    async nextChapter(fromChapter=chapter){let next=fromChapter+1;while(next<view.book.sections.length&&view.book.sections[next].linear==='no')next++;if(next<view.book.sections.length){await view.goTo(next);send('start',{index:0,chapter});}else send('end');},
    async search(query){const gen=++searchGeneration;let results=[];if(!query.trim()){view.clearSearch();send('search',{items:[]});return;}for await(const item of view.search({query,matchCase:false})){if(gen!==searchGeneration)return;for(const r of item.subitems||[]){const excerpt=r.excerpt;results.push({cfi:r.cfi,text:typeof excerpt==='string'?excerpt:[excerpt?.pre,excerpt?.match,excerpt?.post].filter(Boolean).join('')});}if(results.length>=150)break;}if(gen===searchGeneration)send('search',{items:results});},
    annotation(mark){annotations.push(mark);view.addAnnotation(mark);},
    removeAnnotation(cfi){annotations=annotations.filter(a=>a.value!==cfi);view.deleteAnnotation({value:cfi});},
    bookmark(){send('bookmark',{cfi:view.lastLocation?.cfi||'',text:view.lastLocation?.tocItem?.label||(prefs.language==='en'?'Bookmark':'Zakładka')});},
    diagnostics(){send('diagnostics',{chapter,sentences:sentences.length,location:view.lastLocation?.cfi,background:getComputedStyle(document.body).backgroundColor});}
};
window.addEventListener('error',e=>send('error',{message:e.message}));
send('ready');
