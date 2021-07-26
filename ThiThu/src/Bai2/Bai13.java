package Bai2;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.text.DecimalFormat;

import javax.swing.JButton;
import javax.swing.JFrame;
import javax.swing.JLabel;
import javax.swing.JOptionPane;
import javax.swing.JTextField;

public class Bai13 extends JFrame{
    public Bai13(){
        this.setTitle("Temperature Conversion");
        this.setSize(400, 200);
        this.setDefaultCloseOperation(3);

        JLabel lb_F = new JLabel("Nhap do F: ");
        lb_F.setBounds(25, 25, 100, 25);
        this.add(lb_F);

        JTextField txt_F = new JTextField("");
        txt_F.setBounds(150, 25, 150, 25);
        this.add(txt_F);

        JLabel lb_C = new JLabel("Do C: ");
        lb_C.setBounds(25, 75, 100, 25);
        this.add(lb_C);

        JTextField txt_C = new JTextField("");
        txt_C.setBounds(150, 75, 150, 25);
        this.add(txt_C);

        JButton btn = new JButton("Change F->C");
        btn.setBounds(50, 125, 100, 25);
        this.add(btn);

        JButton btn1 = new JButton("Change C->F");
        btn1.setBounds(250, 125, 100, 25);
        this.add(btn1);

        btn.addActionListener(new ActionListener(){

            @Override
            public void actionPerformed(ActionEvent arg0) {
                try {
                    if(txt_F.getText()!=""){
                        Double a = (Double.parseDouble(txt_F.getText())-32)*5/9;
                        DecimalFormat dcf = new DecimalFormat("#.##");
                        txt_C.setText(String.valueOf(dcf.format(a)));
                    }
                } catch (Exception e) {
                    JOptionPane.showMessageDialog(null,"Ban chua nhap du lieu!");
                }
            } 
        });

        btn1.addActionListener(new ActionListener(){

            @Override
            public void actionPerformed(ActionEvent arg0) {
                try{
                if(txt_C.getText()!=""){
                    Double b = Double.parseDouble(txt_C.getText())*9/5+32;
                    DecimalFormat dcf = new DecimalFormat("#.##");
                    txt_F.setText(String.valueOf(dcf.format(b)));
                }
                }catch(Exception e)
                {
                    JOptionPane.showMessageDialog(null,"Ban chua nhap du lieu!");
                }
                
            }

        });

        this.setLayout(null);
        this.setVisible(true);
    }
    public static void main(String[] args) {
        new Bai13();
    }
    
}
