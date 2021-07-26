package Bai2;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;

import javax.swing.JButton;
import javax.swing.JFrame;
import javax.swing.JLabel;

public class Bai12 extends JFrame{
    int count =0;
    public Bai12(){
        this.setTitle("Push Counter");
        this.setSize(400, 150);
        this.setDefaultCloseOperation(3);

        JButton btn =  new JButton("Push Me!");
        btn.setBounds(100, 30, 100, 40);
        this.add(btn);

        JLabel lb = new JLabel("Pushes: ");
        lb.setBounds(210, 30, 65, 40);
        this.add(lb);

        JLabel count_lb = new JLabel("0");
        count_lb.setBounds(280, 30, 50, 40);
        this.add(count_lb);

        btn.addActionListener(new ActionListener(){

            @Override
            public void actionPerformed(ActionEvent arg0) {
                
                count ++;
                count_lb.setText(String.valueOf(count));
            }

        });

        

        this.setLayout(null);
        this.setVisible(true);
    }
    public static void main(String[] args) {
        new Bai12();
    }
}
