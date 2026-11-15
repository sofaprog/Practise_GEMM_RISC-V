00000000000102d6 <spmv_csr_scalar>:
   102d6:	lui	t3,0x1a3
   102da:	addi	t3,t3,-1776 # 1a2910 <csr_vals>
   102de:	lui	a6,0x2f7
   102e2:	mv	a7,a1
   102e4:	lui	t1,0x2fa
   102e8:	lui	t4,0x24d
   102ec:	li	a1,22
   102ee:	li	a4,0
   102f0:	addi	a6,a6,-40 # 2f6fd8 <csr_row_ptr+0x8>
   102f4:	addi	t1,t1,-692 # 2f9d4c <csr_row_ptr+0x2d7c>
   102f8:	addi	t4,t4,-912 # 24cc70 <csr_col_idx>
   102fc:	addi	t5,t3,4
   10300:	bgeu	a4,a1,10358 <spmv_csr_scalar+0x82>
   10304:	addiw	a2,a1,-1
   10308:	subw	a2,a2,a4
   1030a:	slli	a2,a2,0x20
   1030c:	slli	a4,a4,0x20
   1030e:	srli	a4,a4,0x20
   10310:	srli	a2,a2,0x20
   10312:	add	a2,a2,a4
   10314:	fmv.w.x	fa5,zero
   10318:	slli	a4,a4,0x2
   1031a:	slli	a2,a2,0x2
   1031c:	add	a3,a4,t3
   10320:	add	a2,a2,t5
   10322:	add	a4,a4,t4
   10324:	lwu	a5,0(a4)
   10328:	flw	fa3,0(a3)
   1032c:	addi	a3,a3,4
   1032e:	slli	a5,a5,0x2
   10330:	add	a5,a5,a0
   10332:	flw	fa4,0(a5)
   10336:	addi	a4,a4,4
   10338:	fmadd.s	fa5,fa3,fa4,fa5
   1033c:	bne	a3,a2,10324 <spmv_csr_scalar+0x4e>
   10340:	fsw	fa5,0(a7)
   10344:	addi	a7,a7,4
   10346:	beq	a6,t1,10366 <spmv_csr_scalar+0x90>
   1034a:	lw	a5,0(a6)
   1034e:	mv	a4,a1
   10350:	addi	a6,a6,4
   10352:	mv	a1,a5
   10354:	bltu	a4,a1,10304 <spmv_csr_scalar+0x2e>
   10358:	fmv.w.x	fa5,zero
   1035c:	addi	a7,a7,4
   1035e:	fsw	fa5,-4(a7)
   10362:	bne	a6,t1,1034a <spmv_csr_scalar+0x74>
   10366:	ret

000000000001042e <spmv_sellcs_rvv_mem>:
   1042e:	addi	sp,sp,-32
   10430:	sd	s2,0(sp)
   10432:	lui	a2,0x3
   10434:	lui	s2,0x2fc
   10438:	sd	s0,16(sp)
   1043a:	sd	s1,8(sp)
   1043c:	addi	a2,a2,-648 # 2d78 <exit-0xd370>
   10440:	mv	s0,a0
   10442:	mv	s1,a1
   10444:	addi	a0,s2,24 # 2fc018 <y_perm>
   10448:	li	a1,0
   1044a:	sd	ra,24(sp)
   1044c:	jal	11206 <memset>
   10450:	lui	t6,0x1a
   10452:	addi	t6,t6,-1520 # 19a10 <sell_slice_ptr>
   10456:	lui	t4,0x1
   10458:	lui	t3,0xe0
   1045c:	lui	t1,0x20
   10460:	addi	t0,t6,4
   10464:	addi	t5,s2,24
   10468:	addi	a3,s2,24
   1046c:	addi	t6,t6,1468
   10470:	addi	t4,t4,-1186 # b5e <exit-0xf58a>
   10474:	li	a6,70
   10478:	li	a2,0
   1047a:	li	s2,8
   1047c:	addi	t3,t3,-440 # dfe48 <sell_col_idx>
   10480:	addi	t1,t1,248 # 200f8 <sell_vals>
   10484:	li	t2,-2
   10486:	mv	a5,t4
   10488:	bgeu	s2,t4,1048e <spmv_sellcs_rvv_mem+0x60>
   1048c:	li	a5,8
   1048e:	sext.w	a7,a5
   10492:	beqz	a6,104d8 <spmv_sellcs_rvv_mem+0xaa>
   10496:	slli	a5,a5,0x20
   10498:	srli	a5,a5,0x20
   1049a:	li	a1,0
   1049c:	vsetvli	zero,a5,e32,m1,ta,ma
   104a0:	slli	a0,a2,0x20
   104a4:	srli	a4,a0,0x1e
   104a8:	add	a0,t3,a4
   104ac:	add	a4,a4,t1
   104ae:	vle32.v	v25,(a3)
   104b2:	vle32.v	v24,(a0)
   104b6:	vle32.v	v26,(a4)
   104ba:	vsll.vi	v24,v24,2
   104be:	addiw	a1,a1,1
   104c0:	vluxei32.v	v24,(s0),v24
   104c4:	vfmul.vv	v24,v26,v24
   104c8:	vfadd.vv	v24,v25,v24
   104cc:	vse32.v	v24,(a3)
   104d0:	addw	a2,a2,a7
   104d4:	bne	a1,a6,104a0 <spmv_sellcs_rvv_mem+0x72>
   104d8:	addiw	t4,t4,-8
   104da:	addi	a3,a3,32
   104de:	beq	t4,t2,104f0 <spmv_sellcs_rvv_mem+0xc2>
   104e2:	lw	a2,0(t0)
   104e6:	lw	a6,0(t6)
   104ea:	addi	t0,t0,4
   104ec:	addi	t6,t6,4
   104ee:	j	10486 <spmv_sellcs_rvv_mem+0x58>
   104f0:	lui	a3,0x3
   104f2:	addi	a3,a3,-648 # 2d78 <exit-0xd370>
   104f6:	lui	a4,0x1a0
   104fa:	addi	a4,a4,-1124 # 19fb9c <sell_row_perm+0x4>
   104fe:	add	a3,a3,t5
   10500:	li	a5,63
   10504:	j	1050a <spmv_sellcs_rvv_mem+0xdc>
   10506:	lw	a5,0(a4)
   10508:	addi	a4,a4,4
   1050a:	flw	fa5,0(t5)
   1050e:	slli	a2,a5,0x20
   10512:	srli	a5,a2,0x1e
   10516:	add	a5,a5,s1
   10518:	fsw	fa5,0(a5)
   1051c:	addi	t5,t5,4
   1051e:	bne	a3,t5,10506 <spmv_sellcs_rvv_mem+0xd8>
   10522:	ld	ra,24(sp)
   10524:	ld	s0,16(sp)
   10526:	ld	s1,8(sp)
   10528:	ld	s2,0(sp)
   1052a:	addi	sp,sp,32
   1052c:	ret

000000000001052e <spmv_csr_rvv_slide>:
   1052e:	mv	a7,a0
   10530:	lui	t1,0x2f7
   10534:	lui	t4,0x2fa
   10538:	lui	a6,0x1a3
   1053c:	lui	a0,0x24d
   10540:	addi	t1,t1,-40 # 2f6fd8 <csr_row_ptr+0x8>
   10544:	mv	t3,a1
   10546:	addi	t4,t4,-692 # 2f9d4c <csr_row_ptr+0x2d7c>
   1054a:	li	a2,22
   1054c:	li	a3,0
   1054e:	addi	a6,a6,-1776 # 1a2910 <csr_vals>
   10552:	addi	a0,a0,-912 # 24cc70 <csr_col_idx>
   10556:	fmv.w.x	fa5,zero
   1055a:	bgeu	a3,a2,105a8 <spmv_csr_rvv_slide+0x7a>
   1055e:	slli	a4,a3,0x20
   10562:	srli	a5,a4,0x1e
   10566:	subw	a4,a2,a3
   1056a:	slli	a4,a4,0x20
   1056c:	add	a1,a6,a5
   10570:	srli	a4,a4,0x20
   10572:	add	a5,a5,a0
   10574:	vsetvli	a4,a4,e32,m1,ta,ma
   10578:	vle32.v	v25,(a1)
   1057c:	vle32.v	v24,(a5)
   10580:	vsll.vi	v24,v24,2
   10584:	vluxei32.v	v24,(a7),v24
   10588:	vfmul.vv	v25,v25,v24
   1058c:	beqz	a4,105a2 <spmv_csr_rvv_slide+0x74>
   1058e:	li	a5,0
   10590:	vslidedown.vx	v24,v25,a5
   10594:	addi	a5,a5,1
   10596:	vfmv.f.s	fa4,v24
   1059a:	fadd.s	fa5,fa5,fa4
   1059e:	bne	a4,a5,10590 <spmv_csr_rvv_slide+0x62>
   105a2:	addw	a3,a3,a4
   105a4:	bltu	a3,a2,1055e <spmv_csr_rvv_slide+0x30>
   105a8:	fsw	fa5,0(t3)
   105ac:	addi	t3,t3,4
   105ae:	beq	t4,t1,105be <spmv_csr_rvv_slide+0x90>
   105b2:	lw	a5,0(t1)
   105b6:	mv	a3,a2
   105b8:	addi	t1,t1,4
   105ba:	mv	a2,a5
   105bc:	j	10556 <spmv_csr_rvv_slide+0x28>
   105be:	ret

00000000000105c0 <spmv_sellcs_rvv>:
   105c0:	addi	sp,sp,-48
   105c2:	sd	s0,40(sp)
   105c4:	sd	s1,32(sp)
   105c6:	lui	s0,0x1
   105c8:	lui	s1,0x1a
   105ca:	addi	s1,s1,-1520 # 19a10 <sell_slice_ptr>
   105ce:	addi	s0,s0,-1186 # b5e <exit-0xf58a>
   105d2:	lui	t0,0x20
   105d6:	lui	t6,0xe0
   105da:	lui	t5,0x1a0
   105de:	sd	s2,24(sp)
   105e0:	sd	s3,16(sp)
   105e2:	sd	s4,8(sp)
   105e4:	sd	s5,0(sp)
   105e6:	mv	a6,a0
   105e8:	addi	s2,s1,4
   105ec:	mv	t2,a1
   105ee:	addi	s1,s1,1468
   105f2:	li	a0,70
   105f6:	li	t3,0
   105f8:	addi	t0,t0,248 # 200f8 <sell_vals>
   105fc:	addi	t6,t6,-440 # dfe48 <sell_col_idx>
   10600:	addi	t5,t5,-1128 # 19fb98 <sell_row_perm>
   10604:	mv	s5,s0
   10606:	li	s4,8
   10608:	li	s3,-2
   1060a:	subw	t4,s5,s0
   1060e:	mv	a1,s0
   10610:	bgeu	s4,s0,10616 <spmv_sellcs_rvv+0x56>
   10614:	li	a1,8
   10616:	slli	a5,a1,0x20
   1061a:	sext.w	t1,a1
   1061e:	li	a7,0
   10620:	srli	a1,a5,0x1e
   10624:	addw	a4,a7,t3
   10628:	subw	a5,t1,a7
   1062c:	slli	a3,a4,0x20
   10630:	slli	a5,a5,0x20
   10632:	srli	a4,a3,0x1e
   10636:	srli	a5,a5,0x20
   10638:	add	a3,t0,a4
   1063c:	vsetvli	a5,a5,e32,m1,ta,ma
   10640:	add	a4,a4,t6
   10642:	vmv.v.i	v25,0
   10646:	beqz	a0,10668 <spmv_sellcs_rvv+0xa8>
   10648:	li	a2,0
   1064a:	addiw	a2,a2,1
   1064c:	vle32.v	v26,(a3)
   10650:	vle32.v	v24,(a4)
   10654:	add	a3,a3,a1
   10656:	vsll.vi	v24,v24,2
   1065a:	add	a4,a4,a1
   1065c:	vluxei32.v	v24,(a6),v24
   10660:	vfmacc.vv	v25,v26,v24
   10664:	bne	a2,a0,1064a <spmv_sellcs_rvv+0x8a>
   10668:	addw	a4,t4,a7
   1066c:	slli	a3,a4,0x20
   10670:	srli	a4,a3,0x1e
   10674:	add	a4,a4,t5
   10676:	vle32.v	v24,(a4)
   1067a:	addw	a7,a5,a7
   1067e:	vsll.vi	v24,v24,2
   10682:	vsuxei32.v	v25,(t2),v24
   10686:	bltu	a7,t1,10624 <spmv_sellcs_rvv+0x64>
   1068a:	addiw	s0,s0,-8
   1068c:	beq	s0,s3,1069c <spmv_sellcs_rvv+0xdc>
   10690:	lw	t3,0(s2)
   10694:	lw	a0,0(s1)
   10696:	addi	s2,s2,4
   10698:	addi	s1,s1,4
   1069a:	j	1060a <spmv_sellcs_rvv+0x4a>
   1069c:	ld	s0,40(sp)
   1069e:	ld	s1,32(sp)
   106a0:	ld	s2,24(sp)
   106a2:	ld	s3,16(sp)
   106a4:	ld	s4,8(sp)
   106a6:	ld	s5,0(sp)
   106a8:	addi	sp,sp,48
   106aa:	ret

00000000000106ac <spmv_csr_rvv_acc>:
   106ac:	lui	t5,0x2f7
   106b0:	lui	t0,0x2fa
   106b4:	lui	a7,0x1a3
   106b8:	lui	a6,0x24d
   106bc:	vsetvli	a3,zero,e32,m1,ta,ma
   106c0:	mv	t1,a0
   106c2:	addi	t5,t5,-40 # 2f6fd8 <csr_row_ptr+0x8>
   106c6:	mv	t6,a1
   106c8:	addi	t0,t0,-692 # 2f9d4c <csr_row_ptr+0x2d7c>
   106cc:	li	t4,22
   106ce:	li	a4,0
   106d0:	sext.w	t3,a3
   106d4:	addi	a7,a7,-1776 # 1a2910 <csr_vals>
   106d8:	addi	a6,a6,-912 # 24cc70 <csr_col_idx>
   106dc:	vmv.v.i	v27,0
   106e0:	slli	a5,a4,0x20
   106e4:	srli	a5,a5,0x20
   106e6:	slli	a0,t4,0x20
   106ea:	srli	a0,a0,0x20
   106ec:	add	a2,a5,a3
   106f0:	vmv1r.v	v25,v27
   106f4:	bgeu	a0,a2,10700 <spmv_csr_rvv_acc+0x54>
   106f8:	j	1072c <spmv_csr_rvv_acc+0x80>
   106fa:	slli	a5,a4,0x20
   106fe:	srli	a5,a5,0x20
   10700:	addw	a4,a4,t3
   10704:	slli	a2,a4,0x20
   10708:	slli	a5,a5,0x2
   1070a:	srli	a2,a2,0x20
   1070c:	add	a1,a7,a5
   10710:	add	a2,a2,a3
   10712:	add	a5,a5,a6
   10714:	vle32.v	v26,(a1)
   10718:	vle32.v	v24,(a5)
   1071c:	vsll.vi	v24,v24,2
   10720:	vluxei32.v	v24,(t1),v24
   10724:	vfmacc.vv	v25,v26,v24
   10728:	bgeu	a0,a2,106fa <spmv_csr_rvv_acc+0x4e>
   1072c:	vmv1r.v	v24,v27
   10730:	bgeu	a4,t4,1076a <spmv_csr_rvv_acc+0xbe>
   10734:	slli	a5,a4,0x20
   10738:	srli	a2,a5,0x1e
   1073c:	subw	a5,t4,a4
   10740:	slli	a5,a5,0x20
   10742:	srli	a5,a5,0x20
   10744:	vsetvli	zero,a5,e32,m1,ta,ma
   10748:	add	a4,a7,a2
   1074c:	add	a2,a2,a6
   1074e:	vle32.v	v24,(a4)
   10752:	vle32.v	v26,(a2)
   10756:	vsll.vi	v26,v26,2
   1075a:	vluxei32.v	v26,(t1),v26
   1075e:	vfmul.vv	v24,v24,v26
   10762:	vfredusum.vs	v24,v24,v27
   10766:	vsetvli	a3,zero,e32,m1,ta,ma
   1076a:	vfredusum.vs	v25,v25,v24
   1076e:	vfmv.f.s	fa5,v25
   10772:	fsw	fa5,0(t6)
   10776:	addi	t6,t6,4
   10778:	beq	t0,t5,10788 <spmv_csr_rvv_acc+0xdc>
   1077c:	lw	a5,0(t5)
   10780:	mv	a4,t4
   10782:	addi	t5,t5,4
   10784:	mv	t4,a5
   10786:	j	106e0 <spmv_csr_rvv_acc+0x34>
   10788:	ret

000000000001078a <spmv_csr_rvv_red>:
   1078a:	mv	a7,a0
   1078c:	lui	t1,0x2f7
   10790:	lui	t4,0x2fa
   10794:	lui	a6,0x1a3
   10798:	lui	a0,0x24d
   1079c:	addi	t1,t1,-40 # 2f6fd8 <csr_row_ptr+0x8>
   107a0:	mv	t3,a1
   107a2:	addi	t4,t4,-692 # 2f9d4c <csr_row_ptr+0x2d7c>
   107a6:	li	a2,22
   107a8:	li	a4,0
   107aa:	addi	a6,a6,-1776 # 1a2910 <csr_vals>
   107ae:	addi	a0,a0,-912 # 24cc70 <csr_col_idx>
   107b2:	fmv.w.x	fa5,zero
   107b6:	bgeu	a4,a2,107fe <spmv_csr_rvv_red+0x74>
   107ba:	subw	a5,a2,a4
   107be:	slli	a1,a4,0x20
   107c2:	slli	a5,a5,0x20
   107c4:	srli	a3,a1,0x1e
   107c8:	srli	a5,a5,0x20
   107ca:	vsetvli	a5,a5,e32,m1,ta,ma
   107ce:	add	a1,a6,a3
   107d2:	addw	a4,a4,a5
   107d4:	add	a3,a3,a0
   107d6:	vle32.v	v24,(a1)
   107da:	vle32.v	v25,(a3)
   107de:	vmv.v.i	v26,0
   107e2:	vsll.vi	v25,v25,2
   107e6:	vluxei32.v	v25,(a7),v25
   107ea:	vfmul.vv	v24,v24,v25
   107ee:	vfredosum.vs	v24,v24,v26
   107f2:	vfmv.f.s	fa4,v24
   107f6:	fadd.s	fa5,fa5,fa4
   107fa:	bltu	a4,a2,107ba <spmv_csr_rvv_red+0x30>
   107fe:	fsw	fa5,0(t3)
   10802:	addi	t3,t3,4
   10804:	beq	t4,t1,10814 <spmv_csr_rvv_red+0x8a>
   10808:	lw	a5,0(t1)
   1080c:	mv	a4,a2
   1080e:	addi	t1,t1,4
   10810:	mv	a2,a5
   10812:	j	107b2 <spmv_csr_rvv_red+0x28>
   10814:	ret

