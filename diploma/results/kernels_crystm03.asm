00000000000102d6 <spmv_csr_scalar>:
   102d6:	lui	t3,0x500
   102da:	addi	t3,t3,-424 # 4ffe58 <csr_vals>
   102de:	lui	a6,0x974
   102e2:	mv	a7,a1
   102e4:	lui	t1,0x98c
   102e8:	lui	t4,0x73a
   102ec:	li	a1,8
   102ee:	li	a4,0
   102f0:	addi	a6,a6,304 # 974130 <csr_row_ptr+0x8>
   102f4:	addi	t1,t1,780 # 98c30c <csr_row_ptr+0x181e4>
   102f8:	addi	t4,t4,-64 # 739fc0 <csr_col_idx>
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

0000000000010432 <spmv_sellcs_rvv_mem>:
   10432:	addi	sp,sp,-32
   10434:	sd	s2,0(sp)
   10436:	lui	a2,0x18
   10438:	lui	s2,0x98e
   1043c:	sd	s0,16(sp)
   1043e:	sd	s1,8(sp)
   10440:	mv	s0,a0
   10442:	mv	s1,a1
   10444:	addi	a2,a2,480 # 181e0 <signal+0x44>
   10448:	li	a1,0
   1044a:	addi	a0,s2,-920 # 98dc68 <y_perm>
   1044e:	sd	ra,24(sp)
   10450:	jal	111e0 <memset>
   10454:	lui	t4,0x4fd
   10458:	lui	t5,0x4fa
   1045c:	lui	t6,0x500
   10460:	lui	t1,0x296
   10464:	lui	a7,0x4a
   10468:	addi	t4,t4,-484 # 4fce1c <sell_slice_ptr+0x4>
   1046c:	addi	t5,t5,-548 # 4f9ddc <sell_slice_len+0x4>
   10470:	addi	t3,s2,-920
   10474:	addi	t6,t6,-428 # 4ffe54 <sell_slice_ptr+0x303c>
   10478:	addi	a3,s2,-920
   1047c:	li	a6,12
   1047e:	li	a1,0
   10480:	addi	t1,t1,-744 # 295d18 <sell_col_idx>
   10484:	addi	a7,a7,-456 # 49e38 <sell_vals>
   10488:	vsetivli	zero,8,e32,m1,ta,ma
   1048c:	li	a2,0
   1048e:	beqz	a6,104c8 <spmv_sellcs_rvv_mem+0x96>
   10492:	slli	a0,a1,0x20
   10496:	srli	a4,a0,0x1e
   1049a:	add	a0,t1,a4
   1049e:	add	a4,a4,a7
   104a0:	vle32.v	v25,(a3)
   104a4:	vle32.v	v24,(a0)
   104a8:	vle32.v	v26,(a4)
   104ac:	vsll.vi	v24,v24,2
   104b0:	addiw	a2,a2,1
   104b2:	vluxei32.v	v24,(s0),v24
   104b6:	vfmul.vv	v24,v26,v24
   104ba:	vfadd.vv	v24,v25,v24
   104be:	vse32.v	v24,(a3)
   104c2:	addiw	a1,a1,8
   104c4:	bne	a2,a6,10492 <spmv_sellcs_rvv_mem+0x60>
   104c8:	addi	a3,a3,32
   104cc:	beq	t4,t6,104de <spmv_sellcs_rvv_mem+0xac>
   104d0:	lw	a1,0(t4)
   104d4:	lw	a6,0(t5)
   104d8:	addi	t4,t4,4
   104da:	addi	t5,t5,4
   104dc:	j	1048c <spmv_sellcs_rvv_mem+0x5a>
   104de:	lui	a3,0x18
   104e0:	addi	a3,a3,480 # 181e0 <signal+0x44>
   104e4:	lui	a4,0x4e2
   104e8:	addi	a4,a4,-1028 # 4e1bfc <sell_row_perm+0x4>
   104ec:	add	a3,a3,t3
   104ee:	li	a5,3
   104f0:	j	104f6 <spmv_sellcs_rvv_mem+0xc4>
   104f2:	lw	a5,0(a4)
   104f4:	addi	a4,a4,4
   104f6:	flw	fa5,0(t3)
   104fa:	slli	a2,a5,0x20
   104fe:	srli	a5,a2,0x1e
   10502:	add	a5,a5,s1
   10504:	fsw	fa5,0(a5)
   10508:	addi	t3,t3,4
   1050a:	bne	a3,t3,104f2 <spmv_sellcs_rvv_mem+0xc0>
   1050e:	ld	ra,24(sp)
   10510:	ld	s0,16(sp)
   10512:	ld	s1,8(sp)
   10514:	ld	s2,0(sp)
   10516:	addi	sp,sp,32
   10518:	ret

000000000001051a <spmv_csr_rvv_slide>:
   1051a:	mv	a7,a0
   1051c:	lui	t1,0x974
   10520:	lui	t4,0x98c
   10524:	lui	a6,0x500
   10528:	lui	a0,0x73a
   1052c:	addi	t1,t1,304 # 974130 <csr_row_ptr+0x8>
   10530:	mv	t3,a1
   10532:	addi	t4,t4,780 # 98c30c <csr_row_ptr+0x181e4>
   10536:	li	a2,8
   10538:	li	a3,0
   1053a:	addi	a6,a6,-424 # 4ffe58 <csr_vals>
   1053e:	addi	a0,a0,-64 # 739fc0 <csr_col_idx>
   10542:	fmv.w.x	fa5,zero
   10546:	bgeu	a3,a2,10594 <spmv_csr_rvv_slide+0x7a>
   1054a:	slli	a4,a3,0x20
   1054e:	srli	a5,a4,0x1e
   10552:	subw	a4,a2,a3
   10556:	slli	a4,a4,0x20
   10558:	add	a1,a6,a5
   1055c:	srli	a4,a4,0x20
   1055e:	add	a5,a5,a0
   10560:	vsetvli	a4,a4,e32,m1,ta,ma
   10564:	vle32.v	v25,(a1)
   10568:	vle32.v	v24,(a5)
   1056c:	vsll.vi	v24,v24,2
   10570:	vluxei32.v	v24,(a7),v24
   10574:	vfmul.vv	v25,v25,v24
   10578:	beqz	a4,1058e <spmv_csr_rvv_slide+0x74>
   1057a:	li	a5,0
   1057c:	vslidedown.vx	v24,v25,a5
   10580:	addi	a5,a5,1
   10582:	vfmv.f.s	fa4,v24
   10586:	fadd.s	fa5,fa5,fa4
   1058a:	bne	a4,a5,1057c <spmv_csr_rvv_slide+0x62>
   1058e:	addw	a3,a3,a4
   10590:	bltu	a3,a2,1054a <spmv_csr_rvv_slide+0x30>
   10594:	fsw	fa5,0(t3)
   10598:	addi	t3,t3,4
   1059a:	beq	t4,t1,105aa <spmv_csr_rvv_slide+0x90>
   1059e:	lw	a5,0(t1)
   105a2:	mv	a3,a2
   105a4:	addi	t1,t1,4
   105a6:	mv	a2,a5
   105a8:	j	10542 <spmv_csr_rvv_slide+0x28>
   105aa:	ret

00000000000105ac <spmv_sellcs_rvv>:
   105ac:	addi	sp,sp,-32
   105ae:	sd	s1,16(sp)
   105b0:	sd	s2,8(sp)
   105b2:	sd	s3,0(sp)
   105b4:	lui	s1,0x4fd
   105b8:	lui	s2,0x4fa
   105bc:	lui	s3,0x500
   105c0:	lui	t5,0x4a
   105c4:	lui	t4,0x296
   105c8:	lui	t3,0x4e2
   105cc:	sd	s0,24(sp)
   105ce:	mv	t6,a1
   105d0:	addi	s1,s1,-484 # 4fce1c <sell_slice_ptr+0x4>
   105d4:	addi	s2,s2,-548 # 4f9ddc <sell_slice_len+0x4>
   105d8:	addi	s3,s3,-428 # 4ffe54 <sell_slice_ptr+0x303c>
   105dc:	li	a7,0
   105de:	li	a6,12
   105e0:	li	t1,0
   105e2:	addi	t5,t5,-456 # 49e38 <sell_vals>
   105e6:	addi	t4,t4,-744 # 295d18 <sell_col_idx>
   105ea:	addi	t3,t3,-1032 # 4e1bf8 <sell_row_perm>
   105ee:	li	t2,8
   105f0:	li	t0,7
   105f2:	slli	a5,a6,0x20
   105f6:	srli	s0,a5,0x1b
   105fa:	li	a1,0
   105fc:	addw	a3,a1,t1
   10600:	subw	a5,t2,a1
   10604:	slli	a4,a3,0x20
   10608:	slli	a5,a5,0x20
   1060a:	srli	a3,a4,0x1e
   1060e:	srli	a5,a5,0x20
   10610:	add	a4,t5,a3
   10614:	vsetvli	a5,a5,e32,m1,ta,ma
   10618:	add	a3,a3,t4
   1061a:	vmv.v.i	v25,0
   1061e:	beqz	a6,10646 <spmv_sellcs_rvv+0x9a>
   10622:	add	a2,a4,s0
   10626:	vle32.v	v26,(a4)
   1062a:	addi	a4,a4,32
   1062e:	vle32.v	v24,(a3)
   10632:	addi	a3,a3,32
   10636:	vsll.vi	v24,v24,2
   1063a:	vluxei32.v	v24,(a0),v24
   1063e:	vfmacc.vv	v25,v26,v24
   10642:	bne	a4,a2,10626 <spmv_sellcs_rvv+0x7a>
   10646:	addw	a4,a7,a1
   1064a:	slli	a3,a4,0x20
   1064e:	srli	a4,a3,0x1e
   10652:	add	a4,a4,t3
   10654:	vle32.v	v24,(a4)
   10658:	addw	a1,a1,a5
   1065a:	vsll.vi	v24,v24,2
   1065e:	vsuxei32.v	v25,(t6),v24
   10662:	bgeu	t0,a1,105fc <spmv_sellcs_rvv+0x50>
   10666:	addiw	a7,a7,8
   10668:	beq	s3,s1,1067a <spmv_sellcs_rvv+0xce>
   1066c:	lw	t1,0(s1)
   10670:	lw	a6,0(s2)
   10674:	addi	s1,s1,4
   10676:	addi	s2,s2,4
   10678:	j	105f2 <spmv_sellcs_rvv+0x46>
   1067a:	ld	s0,24(sp)
   1067c:	ld	s1,16(sp)
   1067e:	ld	s2,8(sp)
   10680:	ld	s3,0(sp)
   10682:	addi	sp,sp,32
   10684:	ret

0000000000010686 <spmv_csr_rvv_acc>:
   10686:	lui	t5,0x974
   1068a:	lui	t0,0x98c
   1068e:	lui	a7,0x500
   10692:	lui	a6,0x73a
   10696:	vsetvli	a3,zero,e32,m1,ta,ma
   1069a:	mv	t1,a0
   1069c:	addi	t5,t5,304 # 974130 <csr_row_ptr+0x8>
   106a0:	mv	t6,a1
   106a2:	addi	t0,t0,780 # 98c30c <csr_row_ptr+0x181e4>
   106a6:	li	t4,8
   106a8:	li	a4,0
   106aa:	sext.w	t3,a3
   106ae:	addi	a7,a7,-424 # 4ffe58 <csr_vals>
   106b2:	addi	a6,a6,-64 # 739fc0 <csr_col_idx>
   106b6:	vmv.v.i	v27,0
   106ba:	slli	a5,a4,0x20
   106be:	srli	a5,a5,0x20
   106c0:	slli	a0,t4,0x20
   106c4:	srli	a0,a0,0x20
   106c6:	add	a2,a5,a3
   106ca:	vmv1r.v	v25,v27
   106ce:	bgeu	a0,a2,106da <spmv_csr_rvv_acc+0x54>
   106d2:	j	10706 <spmv_csr_rvv_acc+0x80>
   106d4:	slli	a5,a4,0x20
   106d8:	srli	a5,a5,0x20
   106da:	addw	a4,a4,t3
   106de:	slli	a2,a4,0x20
   106e2:	slli	a5,a5,0x2
   106e4:	srli	a2,a2,0x20
   106e6:	add	a1,a7,a5
   106ea:	add	a2,a2,a3
   106ec:	add	a5,a5,a6
   106ee:	vle32.v	v26,(a1)
   106f2:	vle32.v	v24,(a5)
   106f6:	vsll.vi	v24,v24,2
   106fa:	vluxei32.v	v24,(t1),v24
   106fe:	vfmacc.vv	v25,v26,v24
   10702:	bgeu	a0,a2,106d4 <spmv_csr_rvv_acc+0x4e>
   10706:	vmv1r.v	v24,v27
   1070a:	bgeu	a4,t4,10744 <spmv_csr_rvv_acc+0xbe>
   1070e:	slli	a5,a4,0x20
   10712:	srli	a2,a5,0x1e
   10716:	subw	a5,t4,a4
   1071a:	slli	a5,a5,0x20
   1071c:	srli	a5,a5,0x20
   1071e:	vsetvli	zero,a5,e32,m1,ta,ma
   10722:	add	a4,a7,a2
   10726:	add	a2,a2,a6
   10728:	vle32.v	v24,(a4)
   1072c:	vle32.v	v26,(a2)
   10730:	vsll.vi	v26,v26,2
   10734:	vluxei32.v	v26,(t1),v26
   10738:	vfmul.vv	v24,v24,v26
   1073c:	vfredusum.vs	v24,v24,v27
   10740:	vsetvli	a3,zero,e32,m1,ta,ma
   10744:	vfredusum.vs	v25,v25,v24
   10748:	vfmv.f.s	fa5,v25
   1074c:	fsw	fa5,0(t6)
   10750:	addi	t6,t6,4
   10752:	beq	t0,t5,10762 <spmv_csr_rvv_acc+0xdc>
   10756:	lw	a5,0(t5)
   1075a:	mv	a4,t4
   1075c:	addi	t5,t5,4
   1075e:	mv	t4,a5
   10760:	j	106ba <spmv_csr_rvv_acc+0x34>
   10762:	ret

0000000000010764 <spmv_csr_rvv_red>:
   10764:	mv	a7,a0
   10766:	lui	t1,0x974
   1076a:	lui	t4,0x98c
   1076e:	lui	a6,0x500
   10772:	lui	a0,0x73a
   10776:	addi	t1,t1,304 # 974130 <csr_row_ptr+0x8>
   1077a:	mv	t3,a1
   1077c:	addi	t4,t4,780 # 98c30c <csr_row_ptr+0x181e4>
   10780:	li	a2,8
   10782:	li	a4,0
   10784:	addi	a6,a6,-424 # 4ffe58 <csr_vals>
   10788:	addi	a0,a0,-64 # 739fc0 <csr_col_idx>
   1078c:	fmv.w.x	fa5,zero
   10790:	bgeu	a4,a2,107d8 <spmv_csr_rvv_red+0x74>
   10794:	subw	a5,a2,a4
   10798:	slli	a1,a4,0x20
   1079c:	slli	a5,a5,0x20
   1079e:	srli	a3,a1,0x1e
   107a2:	srli	a5,a5,0x20
   107a4:	vsetvli	a5,a5,e32,m1,ta,ma
   107a8:	add	a1,a6,a3
   107ac:	addw	a4,a4,a5
   107ae:	add	a3,a3,a0
   107b0:	vle32.v	v24,(a1)
   107b4:	vle32.v	v25,(a3)
   107b8:	vmv.v.i	v26,0
   107bc:	vsll.vi	v25,v25,2
   107c0:	vluxei32.v	v25,(a7),v25
   107c4:	vfmul.vv	v24,v24,v25
   107c8:	vfredosum.vs	v24,v24,v26
   107cc:	vfmv.f.s	fa4,v24
   107d0:	fadd.s	fa5,fa5,fa4
   107d4:	bltu	a4,a2,10794 <spmv_csr_rvv_red+0x30>
   107d8:	fsw	fa5,0(t3)
   107dc:	addi	t3,t3,4
   107de:	beq	t4,t1,107ee <spmv_csr_rvv_red+0x8a>
   107e2:	lw	a5,0(t1)
   107e6:	mv	a4,a2
   107e8:	addi	t1,t1,4
   107ea:	mv	a2,a5
   107ec:	j	1078c <spmv_csr_rvv_red+0x28>
   107ee:	ret

