# Recorte manual de peças da imagem da vila (OpenCV GrabCut com polígono). Roda no computador, não no GitHub.
import cv2, numpy as np, sys
from PIL import Image
src = cv2.imread('arte/referencias/vila_principal_original.png')
POLYS = {
 'estatua': [(1268,300),(1262,240),(1274,60),(1300,12),(1442,12),(1462,60),(1462,250),(1400,306),(1340,314)],
 'fogueira': [(622,538),(640,470),(662,405),(692,405),(722,470),(740,538),(680,550)],
 'carroca_coberta': [(270,700),(300,645),(345,640),(395,690),(398,745),(360,775),(300,770),(268,735)],
 'arvore_outono': [(700,150),(705,40),(760,0),(860,0),(900,60),(895,170),(840,235),(800,250),(760,230)],
 'lampiao': [(828,230),(850,215),(878,250),(878,300),(845,312),(830,300)],
}
for n in (sys.argv[1:] or POLYS):
    P = np.array(POLYS[n]); x0,y0 = P.min(0)-14; x1,y1 = P.max(0)+14
    x0,y0 = max(0,x0),max(0,y0)
    img = src[y0:y1, x0:x1].copy()
    poly = (P - [x0,y0]).astype(np.int32)
    mask = np.full(img.shape[:2], cv2.GC_BGD, np.uint8)
    cv2.fillPoly(mask, [poly], cv2.GC_PR_FGD)
    inner = cv2.erode((mask==cv2.GC_PR_FGD).astype(np.uint8), np.ones((15,15),np.uint8))
    mask[inner==1] = cv2.GC_FGD if n in ('estatua',) else cv2.GC_PR_FGD
    bg = np.zeros((1,65)); fg = np.zeros((1,65))
    cv2.grabCut(img, mask, None, bg, fg, 8, cv2.GC_INIT_WITH_MASK)
    m = np.where((mask==1)|(mask==3),255,0).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3,3),np.uint8))
    m = cv2.GaussianBlur(m,(3,3),0)
    rgba = cv2.cvtColor(img, cv2.COLOR_BGR2RGBA); rgba[:,:,3]=m
    im = Image.fromarray(rgba); bb = im.getchannel('A').point(lambda a:255 if a>24 else 0).getbbox()
    if bb: im = im.crop(bb)
    im.save(f'/tmp/gc/{n}.png'); print(n, im.size)
