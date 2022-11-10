pragma solidity ^0.8.4;
import './libraries/Math.sol';
import './libraries/Safemath.sol';
import './interface/IERC20.sol';
import './interface/IQilin_Factory.sol';
import './interface/IQilin_Callee.sol';
import './interface/IQilin_Pool.sol';
import './QilinERC20.sol';

contract Pool is QilinERC20{
    uint256 public B;
    uint256 public C;
    uint256 public D;
    uint256 public D0;
    uint256 public Xeq;
    uint256 public Yeq;
    uint256 public X_Coord;
    uint256 public Y_Coord;
    uint256 public Peqy;
    uint256 public Peqx;
    uint256 public Ygetp;
    uint256 public Xgetp;
    uint256 public True_Liquid_Y0;
    uint256 public True_Liquid_X0;
    uint256 public True_Liquid_Y;
    uint256 public True_Liquid_X;
    uint256 public X_Coord_Last;
    uint256 public Y_Coord_Last;
    uint256 public Price_local;
    
    uint256 public Tick_range;                      //固定值，留接口修改

    uint256 public Total_debt_X;
    uint256 public Total_debt_Y;
    uint256 public Total_debttoken_X;
    uint256 public Total_debttoken_Y;
    uint256 public Leverage_Max;                    //固定值，留接口修改
    uint256 public funding_Last;                    //系统内记录上一次funding值
    uint256 public fundingtime_Last;                //系统内记录上一次funding时间
    bool public paying_side_Last;                   //系统内记录上一次funding方向
    uint256 public funding_x_8h_upper;              //= 5000000000固定值，留接口修改
    uint256 public Base_rate;                       //= 156200，固定值，留接口修改
    uint256 public N;
    uint256 public N_Last;
    
    address public factory;
    address public tokenX;
    address public tokenY;
    uint256 public Leverage_Margin;                 //开仓杠杆 18位

    uint256 public Total_Liquidity;                 //LPtoken总值

    uint256 public Liquidation_rate;                //维持保证金率
    uint256 public Liquidation_bonus;               //清算人罚金

    uint256 public const18 = 1e18;

    bool Two_white;
    uint256 public fee;
 
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));
    constructor() public {
        factory = msg.sender;
    }

    using Safemath  for uint;

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function initialize(address _tokenX, address _tokenY) external {
        require(msg.sender == factory, 'FORBIDDEN'); // sufficient check
        tokenX = _tokenX;
        tokenY = _tokenY;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFER_FAILED');
    }

    // 获取资金费率
    function Getfundingrate () internal view returns(uint256 funding_x , bool paying_side){
        uint256 XE = Math.cal_times( True_Liquid_X , Peqx , const18 );
        uint256 YE = Math.cal_times( True_Liquid_Y , Peqy , const18 );
        uint256 BE = Math.cal_B_f(XE, YE, D);
        uint256 CE = 2 * const18 - BE;
        uint256 PE = Math.cal_times( Math.cal_price(BE, CE, D, XE, YE) , Peqy , Peqx );
        uint256 PS = Math.cal_times( Math.cal_price(B, C, D, X_Coord, Y_Coord) , Peqy , Peqx );
        if(PS > PE){
            uint256 interest_rate = Math.cal_interest(Ygetp , True_Liquid_Y , Base_rate);
            funding_x = Math.cal_cross(PS , PE , PE) / 5760 + interest_rate;
            paying_side = false;
        }else{
            uint256 interest_rate = Math.cal_interest(Xgetp , True_Liquid_X , Base_rate);
            funding_x = Math.cal_cross(PE , PS , PE) / 5760 + interest_rate;
            paying_side = true;
        }
        if(funding_x * 1920 > funding_x_8h_upper){
            funding_x = funding_x_8h_upper / 1920;
        }
    }

    // 虚拟流动性更新
    function Virtual_Liquidity_Update() internal {
        N = Math.cal_N(True_Liquid_X , B , Peqx , True_Liquid_Y , C , Peqy , True_Liquid_X0 , True_Liquid_Y0); 
        D = D0 * N / const18;
        Xeq = D/2;
        Yeq = Xeq;
        N_Last = N;
    }

    // 添加流动性
    function Add_Liquidity(uint AddX , uint AddY , address to) external lock returns(uint Liquidity){
        X_Coord = Math.cal_times(X_Coord , (True_Liquid_X + AddX) , True_Liquid_X );
        Y_Coord = Math.cal_times(Y_Coord , (True_Liquid_Y + AddY) , True_Liquid_Y );
        Liquidity = Math.cal_times (Total_Liquidity , AddX , True_Liquid_X );
        Total_Liquidity = Total_Liquidity + Liquidity;
        True_Liquid_X = True_Liquid_X + AddX;
        True_Liquid_Y = True_Liquid_Y + AddY;
        QilinERC20._mint(to, Liquidity);
        Virtual_Liquidity_Update();
    }

    // 撤出流动性
    function Burn_Liquidity(uint Liquidity , address to) external lock returns(uint BurX , uint BurY){
        BurX = Math.cal_times(Liquidity , True_Liquid_X , Total_Liquidity );
        BurY = Math.cal_times(Liquidity , True_Liquid_Y , Total_Liquidity );
        X_Coord = Math.cal_times(X_Coord , (True_Liquid_X - BurX) , True_Liquid_X );
        Y_Coord = Math.cal_times(Y_Coord , (True_Liquid_Y - BurY) , True_Liquid_Y );
        True_Liquid_X = True_Liquid_X - BurX;
        True_Liquid_Y = True_Liquid_Y - BurY;
        Total_Liquidity = Total_Liquidity - Liquidity;
        QilinERC20._burn(address(this), Liquidity);
        _safeTransfer(tokenX, to, BurX);
        _safeTransfer(tokenY, to, BurY);
        Virtual_Liquidity_Update();
    }

    //现货/合约 交易，用X买Y input为 delta：用户支付的X值，perp：是否为合约交易，output为 Yget：用户支付的X值所能换出的Y值
    function Trade_XtoY(uint delta, bool perp) internal lock returns(uint Yget) {
        uint deltaX = delta;
        bool check = true;
        while(check == true){
            //计算此时曲线内触发跨tick的X值
            uint X_Coord_Test = Math.cal_times(Xeq , Tick_range , const18);

            //计算对应的Y值
            uint Y_Coord_Test = Math.cal_Y(B, C, D, X_Coord_Test);

            //检测当前输入deltaX是否大于跨tick所需X
            if(deltaX > Math.cal_cross(X_Coord_Test, X_Coord, Peqx)){
                
                //计算累加跨tick前所需X能换得的Y
                Yget += Math.cal_cross(Y_Coord, Y_Coord_Test, Peqy);

                //deltaX减少跨tick所用的这部分X
                deltaX -= Math.cal_cross(X_Coord_Test, X_Coord, Peqx);

                //如果是perp交易，则累加系统内总的Y Position
                if(perp == true) {
                    Ygetp += Math.cal_cross(Y_Coord, Y_Coord_Test, Peqy);
                
                //如果是现货 按这一小笔交易（即跨tick所需X -> Y）的进出更新 X和Y的实际资产存量
                }else{
                    True_Liquid_X += Math.cal_cross(X_Coord_Test, X_Coord, Peqx);
                    True_Liquid_Y -= Math.cal_cross(Y_Coord, Y_Coord_Test, Peqy);
                }

                // 按照跨tick后系统状态更新Peqx Peqy
                Peqy = Math.cal_times(Peqy , Yeq , Y_Coord_Test);
                Peqx = Math.cal_times(Peqx , Xeq , X_Coord_Test);

                //计算跨tick后的曲线斜率所对应的Price_local
                Price_local = Math.cal_times2 (Math.cal_price(B, C, D, X_Coord_Test, Y_Coord_Test) , Y_Coord_Test , Xeq , X_Coord_Test , Yeq );
                
                //更新 跨tick后X Y坐标
                X_Coord = Xeq;
                Y_Coord = Yeq;

                //计算此时对应的B C值
                B = Math.cal_B(X_Coord, Y_Coord, D, Price_local);
                C = 2 * const18 - B; 

                //根据新的各参数 更正流动性
                Virtual_Liquidity_Update();

                //将更新流动性后的参数传入曲线
                X_Coord = Xeq;
                Y_Coord = Yeq;

            }else{
                //记录此时的X Y坐标
                X_Coord_Last = X_Coord;
                Y_Coord_Last = Y_Coord;

                //按剩余deltaX 更新X Y坐标
                X_Coord +=  Math.cal_times(deltaX , Peqx , const18);
                Y_Coord = Math.cal_Y(B, C, D, X_Coord);

                //计算累加这部分X能换得的Y
                Yget += Math.cal_cross(Y_Coord_Last, Y_Coord, Peqy);

                //如果是perp交易，则累加系统内总的Y Position
                if(perp == true){
                    Ygetp += Math.cal_cross(Y_Coord_Last, Y_Coord, Peqy);

                //如果是现货 按这一小笔交易的进出更新 X和Y的实际资产存量
                }else{
                    True_Liquid_X += deltaX;
                    True_Liquid_Y -= Math.cal_cross(Y_Coord_Last, Y_Coord, Peqy);
                }
                check = false;
            }
        }
    }

    //现货/合约 交易，用X买Y，input为 delta：所需的目标Y值， Xmax：用户可以支付的X值上限，perp：是否是合约交易，output为Xin：为换出所需Y值，用户所要支付的精确X值
    function TradeXToExactY(uint delta, uint Xmax, bool perp) internal lock returns(uint Xin) {
        uint deltaY = delta;
        bool check = true;
        while(check == true){
            
            //计算此时曲线内触发跨tick的X值
            uint X_Coord_Test = Math.cal_times(Xeq , Tick_range , const18);

            //计算对应的Y值
            uint Y_Coord_Test = Math.cal_Y(B, C, D, X_Coord_Test);

            //检测所需Y值是否大于跨tick会换出的Y值
            if(deltaY > Math.cal_cross(Y_Coord, Y_Coord_Test, Peqy)){

                //累加所需精确X输入值
                Xin += Math.cal_cross(X_Coord_Test, X_Coord, Peqx);

                //减少对应的目标Y值
                deltaY -= Math.cal_cross(Y_Coord, Y_Coord_Test, Peqy);

                //检测是否为合约交易，是的话更改总position参数，不是的话更改真实流动性参数
                if(perp == true){
                    Ygetp += Math.cal_cross(Y_Coord, Y_Coord_Test, Peqy);
                }else{
                    True_Liquid_X +=  Math.cal_cross(X_Coord_Test, X_Coord, Peqx);
                    True_Liquid_Y -=  Math.cal_cross(Y_Coord, Y_Coord_Test, Peqy);
                }


                // 按照跨tick后系统状态更新Peqx Peqy  计算跨tick后的曲线斜率所对应的Price_local
                Peqy = Math.cal_times(Peqy , Yeq , Y_Coord_Test);
                Peqx = Math.cal_times(Peqx , Xeq , X_Coord_Test);
                Price_local = Math.cal_times2 (Math.cal_price(B, C, D, X_Coord_Test, Y_Coord_Test) , Y_Coord_Test , Xeq , X_Coord_Test , Yeq );
                
                X_Coord = Xeq;
                Y_Coord = Yeq;
                B = Math.cal_B(X_Coord, Y_Coord, D, Price_local);
                C = 2 * const18 - B;
                Virtual_Liquidity_Update();
                X_Coord = Xeq;
                Y_Coord = Yeq;

            }else{
                X_Coord_Last = X_Coord;
                Y_Coord_Last = Y_Coord;
                Y_Coord -= Math.cal_times(deltaY , Peqy , const18);
                X_Coord = Math.cal_X(B, C, D, Y_Coord);
                Xin += Math.cal_cross(X_Coord, X_Coord_Last, Peqx);
                if(perp == true){
                    Ygetp += deltaY;
                }else{
                    True_Liquid_X += Math.cal_cross(X_Coord, X_Coord_Last, Peqx);
                    True_Liquid_Y -= deltaY;
                }
                check = false;
            }
        }
        //对于 现货交易，需检测 计算出的所需X输入值是否小于用户能支付的X值上限
        if(perp == false) require(Xmax > Xin);
    }

    //现货/合约  交易，用Y买X input为Y
    function Trade_YtoX(uint delta , bool perp) internal lock returns(uint Xget) {
        uint deltaY = delta;
        bool check = true;
        while(check == true){

            uint Y_Coord_Test = Math.cal_times(Yeq , Tick_range , const18);
            uint X_Coord_Test = Math.cal_X(B, C, D, Y_Coord_Test);

            if(deltaY > Math.cal_cross(Y_Coord_Test, Y_Coord, Peqy)){

                Xget += Math.cal_cross(X_Coord, X_Coord_Test, Peqx);
                deltaY -= Math.cal_cross(Y_Coord_Test, Y_Coord, Peqy);
                if(perp == true){
                    Xgetp += Math.cal_cross(X_Coord, X_Coord_Test, Peqx);
                }else{
                    True_Liquid_X -= Math.cal_cross(X_Coord, X_Coord_Test, Peqx);
                    True_Liquid_Y += Math.cal_cross(Y_Coord_Test, Y_Coord, Peqy);
                }

                Peqy = Math.cal_times(Peqy , Yeq , Y_Coord_Test);
                Peqx = Math.cal_times(Peqx , Xeq , X_Coord_Test);
                Price_local = Math.cal_times2 (Math.cal_price(B, C, D, X_Coord_Test, Y_Coord_Test) , Y_Coord_Test , Xeq , X_Coord_Test , Yeq );
                
                X_Coord = Xeq;
                Y_Coord = Yeq;
                B = Math.cal_B(X_Coord, Y_Coord, D, Price_local);
                C = 2 * const18 - B;
                Virtual_Liquidity_Update();
                X_Coord = Xeq;
                Y_Coord = Yeq;

            }else{
                X_Coord_Last = X_Coord;
                Y_Coord_Last = Y_Coord;
                Y_Coord += Math.cal_times(deltaY , Peqy , const18);
                X_Coord = Math.cal_X(B, C, D, Y_Coord);
                Xget += Math.cal_cross(X_Coord_Last, X_Coord, Peqx);
                if(perp == true){
                    Xgetp += Math.cal_cross(X_Coord_Last, X_Coord, Peqx);
                }else{
                    True_Liquid_Y += deltaY;
                    True_Liquid_X -= Math.cal_cross(X_Coord_Last, X_Coord, Peqx);
                }
                check = false;
            }
        }
    }

    //现货/合约  交易，用Y买X input为X
    function TradeYToExactX(uint delta, uint Ymax, bool perp) internal lock returns(uint Yin) {
        uint deltaX = delta;
        bool check = true;
        while(check == true){

            uint Y_Coord_Test = Math.cal_times(Yeq , Tick_range , const18);
            uint X_Coord_Test = Math.cal_X(B, C, D, Y_Coord_Test);

            if(deltaX > Math.cal_cross(X_Coord, X_Coord_Test, Peqx)){

                Yin += Math.cal_cross(Y_Coord_Test, Y_Coord, Peqy);
                deltaX -= Math.cal_cross(X_Coord, X_Coord_Test, Peqx);
                if(perp == true){
                    Xgetp += Math.cal_cross(X_Coord, X_Coord_Test, Peqx);
                }else{
                    True_Liquid_Y +=  Math.cal_cross(Y_Coord_Test, Y_Coord, Peqy);
                    True_Liquid_X -=  Math.cal_cross(X_Coord, X_Coord_Test, Peqx);
                }

                Peqy = Math.cal_times(Peqy , Yeq , Y_Coord_Test);
                Peqx = Math.cal_times(Peqx , Xeq , X_Coord_Test);
                Price_local = Math.cal_times2 (Math.cal_price(B, C, D, X_Coord_Test, Y_Coord_Test) , Y_Coord_Test , Xeq , X_Coord_Test , Yeq );
                
                X_Coord = Xeq;
                Y_Coord = Yeq;
                B = Math.cal_B(X_Coord, Y_Coord, D, Price_local);
                C = 2 * const18 - B;
                Virtual_Liquidity_Update();
                X_Coord = Xeq;
                Y_Coord = Yeq;

            }else{
                X_Coord_Last = X_Coord;
                Y_Coord_Last = Y_Coord;
                X_Coord -= Math.cal_times(deltaX , Peqx , const18);
                Y_Coord = Math.cal_Y(B, C, D, X_Coord);
                Yin += Math.cal_cross(Y_Coord, Y_Coord_Last, Peqy);
                if(perp == true){
                    Xgetp += deltaX;
                }else{ 
                    True_Liquid_Y += Math.cal_cross(Y_Coord, Y_Coord_Last, Peqy);
                    True_Liquid_X -= deltaX;
                }
                check = false;
            }
        }
        if(perp == false) require(Ymax > Yin);
    }

    // 总的swap function 现货交易时调用  input为 to：资产输出地址 ，Xout：用户所需Y to exact X 的精准X输出值， Yout：用户所需X to exact Y 的精准X输出值；如果Xout&Yout均为0，则代表用户无需exact，只需将输入资产全部输出即可
    function swap(address to, uint256 Xout, uint256 Yout) external lock{

        //检测，Xout和Yout不可同时大于0
        require(Xout == 0 || Yout == 0);
        // require(to != tokenX && to != tokenY, 'Qilin: INVALID_TO');  不是很理解

        //检测用户转入池的资产量
        uint amountXIn = IERC20(tokenX).balanceOf(address(this)) - True_Liquid_X;
        uint amountYIn = IERC20(tokenY).balanceOf(address(this)) - True_Liquid_Y;
        require(amountXIn > 0 || amountYIn > 0);

        //Xout大于0则代表Y to exact X，并将剩余Y转出
        if(Xout > 0){
            _safeTransfer(tokenY, to, amountYIn - TradeYToExactX(Xout, amountYIn, false));
            _safeTransfer(tokenX, to, Xout);

        //Yout大于0则代表X to exact Y，并将剩余X转出
        }else if(Yout > 0){
            _safeTransfer(tokenX, to, amountXIn - TradeXToExactY(Yout, amountXIn, false));
            _safeTransfer(tokenY, to, Yout);

        //都为0则将用户转入资产全部swap并转出
        }else{
            if(amountXIn > 0) _safeTransfer(tokenY, to, Trade_XtoY(amountXIn, false));
            if(amountYIn > 0) _safeTransfer(tokenX, to, Trade_YtoX(amountYIn, false));
        }
    }


    struct debtbook{
        address user_ID;
        bool token_ID; 
        uint debttoken_amount;
        uint position_amount;
    }


    uint[2] public Margin_reserve;   //记录保证金的总存储量

    mapping(address => mapping(bool => debtbook)) public debt_index;  //将用户address + 债务token（左侧资产还是右侧资产）与存储其debt_token和仓位 对应

    mapping(address => uint[2]) public margin_index;  //将用户address与存储其保证金的数组对应





    //求保证金净值
    function Net_Margin(address userID) internal view returns(uint net){
        net = margin_index[userID][0] + Math.cal_times2(margin_index[userID][1] ,  Price_local , Peqy , Peqx , const18);
        
    }

    //求仓位净值 注：36位
    function Net_Position(address userID) internal view returns(uint net){
        net = debt_index[userID][false].position_amount * const18 + Math.cal_times2(debt_index[userID][true].position_amount , Price_local , Peqy , Peqx , const18 );
    }

    //求债务净值
    function Net_debt(address userID) internal view returns(uint net){
        net = Math.cal_times(debt_index[userID][true].debttoken_amount ,  Total_debt_Y , Total_debttoken_Y) + Math.cal_times( Math.cal_times2(debt_index[userID][false].debttoken_amount ,  Total_debt_X , Price_local , Total_debttoken_X , const18) , Peqy , Peqx);
    }

    //更新debt总账
    function refresh_totalbook() internal {
        (uint funding_x , bool paying_side) = Getfundingrate();
        uint time_gap = block.number - fundingtime_Last;
        fundingtime_Last = block.number;
        uint price = Math.cal_times(Price_local , Peqy , Peqx);
        if(paying_side_Last == false){
            Total_debt_X = Math.cal_times2(Total_debt_X , (const18 + funding_Last) , time_gap , const18 , 1);
            Total_debt_Y = Total_debt_Y - Math.cal_times2(funding_Last , Total_debt_X , price , const18 , const18) * time_gap;
        }else{
            Total_debt_Y = Math.cal_times2(Total_debt_Y , (const18 + funding_Last) , time_gap , const18 , 1);
            Total_debt_X = Total_debt_X - Math.cal_times2(funding_Last , Total_debt_Y , time_gap , price , 1);
        }
        funding_Last = funding_x; 
        paying_side_Last = paying_side;
        }


    //开仓 不允许多空同时开仓
    function Perp_open(uint delta_X, uint delta_Y, bool XtoY, address userID) public lock{
        require(delta_X * delta_Y == 0 && delta_X + delta_Y > 0);
        refresh_totalbook(); 
        require((Net_Margin(userID) +  Net_Position(userID) - Net_debt(userID)) / Leverage_Margin > Math.max (delta_X * const18 + Net_Position(userID), Math.cal_times2(delta_Y , Price_local , Peqy , Peqx , 1) + Net_Position(userID)),'Qilin: NOT ENOUGH MARGIN');
        uint256 Out;
        uint256 In;
        if(XtoY == true){
            if(delta_X > 0){
                Out = Trade_XtoY(delta_X , true);
                In = delta_X;
            }else{
                Out = delta_Y;
                In = TradeXToExactY(delta_Y , 0 , true);
            }
            debt_index[userID][false].debttoken_amount += Math.cal_times(In , Total_debttoken_X , Total_debt_X);
            debt_index[userID][true].position_amount += Out;
            Total_debttoken_X = Math.cal_times(In , Total_debttoken_X , Total_debt_X) + Total_debttoken_X;
            Total_debt_X += In ;
        }else{
            if(delta_X > 0){
                Out = delta_X;
                In = TradeYToExactX(delta_X , 0 , true);
            }else{
                Out = Trade_YtoX(delta_Y , true);
                In = delta_Y;
            }
            debt_index[userID][true].debttoken_amount += Math.cal_times(In , Total_debttoken_Y , Total_debt_Y);
            debt_index[userID][false].position_amount += Out;
            Total_debttoken_Y = Math.cal_times(In , Total_debttoken_Y , Total_debt_Y) + Total_debttoken_Y;
            Total_debt_Y += In ;
        }
    }

    //一键 多空双开
    //function Perp_biopen(uint delta_X, uint delta_Y, address userID) external lock{
    //    require(delta_X * delta_Y == 0 && delta_X + delta_Y > 0);
    //    if(delta_X > 0){
    //        Perp_open(delta_X , 0 , true , userID);
    //        Perp_open(delta_X , 0 , false, userID);
    //    }else{
    //        Perp_open(0 , delta_Y , true , userID);
    //        Perp_open(0 , delta_Y , false, userID);
    //    }
    //}
    

    //平仓 
    function Perp_close(uint delta_X, uint delta_Y, address userID) public lock {
        require(delta_X * delta_Y == 0 && delta_X + delta_Y > 0 && Net_Margin(userID) + Net_Position(userID) > Net_debt(userID) && delta_X <= debt_index[userID][false].position_amount && delta_Y <= debt_index[userID][true].position_amount);
        refresh_totalbook();
        if(delta_X > 0){   
            uint Get = Trade_XtoY(delta_X , true);
            uint Y_close = Math.cal_times2(delta_X , debt_index[userID][true].debttoken_amount , Total_debt_Y , Total_debttoken_Y , debt_index[userID][false].position_amount) ;
            debt_index[userID][false].position_amount -= delta_X;
            Total_debt_Y -= Y_close ; 
            Total_debttoken_Y -= Math.cal_times(debt_index[userID][true].debttoken_amount , delta_X , debt_index[userID][false].position_amount) ;
            debt_index[userID][true].debttoken_amount -= Math.cal_times(debt_index[userID][true].debttoken_amount , delta_X , debt_index[userID][false].position_amount);

            if(Get > Y_close && Two_white == false){
                margin_index[userID][0] += Trade_YtoX(Get - Y_close , false);
            }else if(margin_index[userID][1] + Get > Y_close && Two_white == true){
                margin_index[userID][1] = margin_index[userID][1] + Get - Y_close;
            }else{
                margin_index[userID][0] = margin_index[userID][0] - TradeXToExactY(Y_close - Get - margin_index[userID][1] , margin_index[userID][0], false);
                margin_index[userID][1] = 0;
            }
        }else{
            uint Get = Trade_YtoX(delta_Y , true);
            uint X_close = Math.cal_times2(delta_Y , debt_index[userID][false].debttoken_amount , Total_debt_X , Total_debttoken_X , debt_index[userID][true].position_amount) ;
            debt_index[userID][true].position_amount -= delta_Y;
            Total_debt_X -= X_close ; 
            Total_debttoken_X -= Math.cal_times(debt_index[userID][false].debttoken_amount , delta_Y , debt_index[userID][true].position_amount) ;
            debt_index[userID][false].debttoken_amount -= Math.cal_times(debt_index[userID][false].debttoken_amount , delta_Y , debt_index[userID][true].position_amount);
            
            if(margin_index[userID][0] + Get > X_close){
                margin_index[userID][0] = margin_index[userID][0] + Get - X_close;
            }else{
                margin_index[userID][1] = margin_index[userID][1] - TradeYToExactX(X_close - Get - margin_index[userID][0], margin_index[userID][1], false);
                margin_index[userID][0] = 0;
            }
        }
    }

    //清算 待修改
    function Liquidate(address userID, address _to) external lock {
        require(Net_Margin(userID) + Net_Position(userID) <= Net_debt(userID) || Net_Margin(userID) + Net_Position(userID) - Net_debt(userID) <= Net_Position(userID) * Liquidation_rate);
        _safeTransfer(tokenX, _to ,  margin_index[userID][0] * Liquidation_bonus);
        _safeTransfer(tokenY, _to ,  margin_index[userID][1] * Liquidation_bonus);
        delete margin_index[userID]; //
        debt_index[userID][false].debttoken_amount = 0;
        debt_index[userID][true].debttoken_amount = 0;
        Perp_close(debt_index[userID][false].position_amount, debt_index[userID][true].position_amount, userID);
    }


    //加保证金
    function Add_Margin(address tokenID, address userID) public {
        uint new_margin;
        if(tokenID == tokenY && Two_white == true){
            new_margin = IERC20(tokenID).balanceOf(address(this)) - True_Liquid_Y - Margin_reserve[1];
            margin_index[userID][1] += new_margin;
            Margin_reserve[1] += new_margin;
        }else{
            new_margin = IERC20(tokenID).balanceOf(address(this)) - True_Liquid_X - Margin_reserve[0];
            margin_index[userID][0] += new_margin;
            Margin_reserve[0] += new_margin;
        }
    } 

    //提取保证金
    function WithdrawMargin (address userID , address tokenID, address to, uint amount) internal lock{
        if(tokenID == tokenX){
            require(margin_index[userID][0] > amount);
            margin_index[userID][0] -= amount;
        }else{
            require(margin_index[userID][1] > amount);
            margin_index[userID][1] -= amount;
        }
        require(Net_Margin(userID) + Net_Position(userID) > Net_debt(userID) && Net_Margin(userID) + Net_Position(userID) - Net_debt(userID) > Net_Position(userID) * Liquidation_rate);
        _safeTransfer(tokenID, to, amount);
    }


    //留端口设置保证金杠杆上限
    function Set_LeverageMargin(uint L) external {
        require(msg.sender == factory);
        Leverage_Margin = L;
    }

    //留端口设置funding rate上限
    function Set_fundingrate_upper(uint f) external {
        require(msg.sender == factory);
        funding_x_8h_upper = f;
    }

    //留端口设置 维持保证金率
    function Set_Liquidation_rate(uint rate) external{
        require(msg.sender == factory);
        Liquidation_rate = rate;
    }


    //使真实资产存量等于记录值，可被外部套利者调用
     function skim(address to) external lock {
        _safeTransfer(tokenX, to, IERC20(tokenX).balanceOf(address(this)).sub(True_Liquid_X));
        _safeTransfer(tokenY, to, IERC20(tokenY).balanceOf(address(this)).sub(True_Liquid_Y));
    }



}